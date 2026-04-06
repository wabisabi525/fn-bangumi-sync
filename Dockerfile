#!/usr/bin/env python3
from flask import Flask, render_template, request, jsonify, Response
import sqlite3, requests, json, os, re, threading, time
import urllib.parse
from datetime import datetime, timedelta
from queue import Queue
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger

app = Flask(__name__)

@app.after_request
def add_header(r):
    r.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    r.headers["Pragma"] = "no-cache"
    r.headers["Expires"] = "0"
    return r

CONFIG_FILE = 'config.json'
LOG_QUEUE = Queue()
DB_PATH = os.getenv('DB_PATH', '/db/trimmedia.db')

class SyncManager:
    def __init__(self):
        self.config = self.load_config()
        self.syncing = False
        self.last_log =[]
        self._stop = threading.Event()
        self.scheduler = BackgroundScheduler()
        self.scheduler_job = None
        self.last_sync_time = None
        self.synced = self.load_cache()
    def load_cache(self):
        try:
            with open('synced.json', 'r') as f: return json.load(f)
        except: return[]
    def save_cache(self):
        try:
            with open('synced.json', 'w') as f: json.dump(self.synced, f)
        except: pass
        if self.config.get('sync_mode') == 'auto': self.start_auto_sync()
        
    def load_config(self):
        default = {'bangumi_token': '', 'min_percent': 80, 'user_filter': 'all', 'time_range': 'all', 'sync_mode': 'manual', 'sync_interval': 300}
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, 'r') as f: return {**default, **json.load(f)}
            except: pass
        return default

    def save_config(self, data):
        self.config.update(data)
        try:
            with open(CONFIG_FILE, 'w') as f: json.dump(self.config, f, indent=2)
        except Exception as e: pass
        if self.config.get('sync_mode') == 'auto': self.start_auto_sync()
        else: self.stop_auto_sync()
    
    def log(self, msg):
        t = datetime.now().strftime('%m-%d %H:%M:%S')
        line = f"[{t}] {msg}"
        self.last_log.append(line)
        if len(self.last_log) > 100: self.last_log = self.last_log[-50:]
        LOG_QUEUE.put(line)
        print(line, flush=True)

    def get_users(self):
        try:
            conn = sqlite3.connect(f'file:{DB_PATH}?mode=ro', uri=True)
            cursor = conn.cursor()
            cursor.execute("SELECT guid, username FROM user WHERE status = 1 AND guid != 'default-user-template' ORDER BY username")
            users =[]
            for row in cursor.fetchall():
                uid = row[0]
                uname = row[1] if row[1] else uid[:8]
                users.append({'id': uid, 'name': uname})
            conn.close()
            return users
        except Exception as e: return[]

    def build_query(self, user_guid='all', time_range='all', limit=50, ep_col='NULL'):
        query = f'''
            SELECT p.item_guid, p.user_guid, p.watched, p.ts, p.media_guid, p.create_time, p.update_time,
            i.title as media_title, i.original_title as media_original_title, i.runtime as runtime_mins,
            p1.title as p1_title, p2.title as p2_title, p1.runtime as p1_runtime, p2.runtime as p2_runtime, {ep_col} as ep_number
            FROM item_user_play p LEFT JOIN item i ON p.item_guid = i.guid
            LEFT JOIN item p1 ON i.parent_guid = p1.guid LEFT JOIN item p2 ON p1.parent_guid = p2.guid
            WHERE p.visible = 1
        '''
        params =[]
        if user_guid and user_guid != 'all': query += ' AND p.user_guid = ?'; params.append(user_guid)
        if time_range == '1week': query += ' AND p.update_time >= ?'; params.append(int((datetime.now() - timedelta(days=7)).timestamp() * 1000))
        elif time_range == '1month': query += ' AND p.update_time >= ?'; params.append(int((datetime.now() - timedelta(days=30)).timestamp() * 1000))
        elif time_range == '1day': query += ' AND p.update_time >= ?'; params.append(int((datetime.now() - timedelta(days=1)).timestamp() * 1000))
        query += ' ORDER BY p.update_time DESC LIMIT ?'; params.append(limit)
        return query, params

    def get_records(self, user_guid=None, time_range=None, limit=50):
        try:
            if not os.path.exists(DB_PATH): return {'error': f'数据库不存在: {DB_PATH}'}
            user_guid = user_guid or self.config.get('user_filter', 'all')
            time_range = time_range or self.config.get('time_range', 'all')
            conn = sqlite3.connect(f'file:{DB_PATH}?mode=ro', uri=True)
            conn.row_factory = sqlite3.Row; cursor = conn.cursor()
            
            cursor.execute("PRAGMA table_info(item)")
            cols =[c[1].lower() for c in cursor.fetchall()]
            ep_col = 'NULL'
            for c in['episode_number', 'index_number', 'episode_index', 'sort_index']:
                if c in cols: ep_col = f'i.{c}'; break

            sql, params = self.build_query(user_guid, time_range, limit, ep_col)
            cursor.execute(sql, params)
            records =[]
            for r in cursor.fetchall():
                ts_time = r['update_time'] or r['create_time'] or 0
                if ts_time > 1000000000000: ts_time = ts_time / 1000
                play_time = datetime.fromtimestamp(ts_time).strftime('%Y-%m-%d %H:%M') if ts_time else '-'
                
                is_completed = int(r['watched'] or 0) == 1
                current_pos_sec = int(r['ts'] or 0)
                # 修复缺少 runtime 导致进度为 0 的终极兜底逻辑
                runtime_mins = r['runtime_mins']
                if not runtime_mins: runtime_mins = r['p1_runtime']
                if not runtime_mins: runtime_mins = r['p2_runtime']
                runtime_mins = int(runtime_mins or 24)
                total_sec = runtime_mins * 60
                
                if is_completed: percent = 100.0; status = '已看完'
                else:
                    percent = round(max(0.0, min(100.0, (current_pos_sec / total_sec) * 100)), 1) if total_sec > 0 else 0.0
                    if percent >= self.config.get('min_percent', 80): status = '已看完'
                    elif current_pos_sec > 0: status = '观看中'
                    else: status = '未开始'
                
                base_name = r['media_title'] or r['media_original_title'] or ''
                real_name = base_name
                if r['p2_title'] and r['p1_title']: real_name = r['p1_title'] if r['p2_title'].lower() in r['p1_title'].lower() else f"{r['p2_title']} {r['p1_title']}"
                elif r['p2_title']: real_name = r['p2_title']
                elif r['p1_title']: real_name = r['p1_title']
                if not real_name: real_name = f"视频-{str(r['item_guid'])[:8]}"
                
                episode_num = 1
                if r['ep_number'] is not None:
                    try: episode_num = int(r['ep_number'])
                    except: pass
                else:
                    ep_match = re.search(r'(?:第|E|ep)\s*0*(\d+)(?:集|话|話)?', base_name, re.IGNORECASE)
                    if ep_match: episode_num = int(ep_match.group(1))

                records.append({'media_name': real_name, 'episode_title': base_name, 'episode_num': episode_num, 'play_time': play_time, 'percent': percent, 'status': status})
            conn.close()
            return {'records': records, 'count': len(records), 'pending_count': len([r for r in records if r['status'] == '已看完']), 'filter': {'user': user_guid, 'range': time_range}}
        except Exception as e: return {'error': str(e)}

    def start_auto_sync(self):
        self.stop_auto_sync()
        interval = self.config.get('sync_interval', 300)
        self.scheduler_job = self.scheduler.add_job(func=self._auto_sync_task, trigger=IntervalTrigger(seconds=interval), id='auto_sync_job', replace_existing=True, max_instances=1)
        if not self.scheduler.running: self.scheduler.start()
        self.log(f'自动同步已启动，间隔: {interval}秒'); return True
    
    def stop_auto_sync(self):
        if self.scheduler_job: self.scheduler_job.remove(); self.scheduler_job = None
        self.log('自动同步已停止'); return True
    
    def _auto_sync_task(self):
        if self.config.get('sync_mode') == 'auto' and not self.syncing: 
            self.run_sync(user_guid=self.config.get('user_filter', 'all'), time_range=self.config.get('time_range', 'all'))
    
    def get_sync_status(self):
        return {'mode': self.config.get('sync_mode', 'manual'), 'is_running': self.scheduler.running, 'has_job': self.scheduler_job is not None, 'last_sync_time': self.last_sync_time, 'syncing_now': self.syncing}

    def _do_search(self, kw):
        headers = {'Authorization': f"Bearer {self.config.get('bangumi_token', '')}", 'User-Agent': 'fn-sync/2.0'}
        try:
            r = requests.post('https://api.bgm.tv/v0/search/subjects', headers=headers, json={"keyword": kw, "filter": {"type": [2, 6]}}, timeout=10)
            if r.status_code == 200 and r.json().get('data'): return [{'id': i['id'], 'name': i.get('name_cn') or i.get('name')} for i in r.json()['data'][:5]]
        except: pass
        try:
            r = requests.get(f'https://api.bgm.tv/search/subject/{urllib.parse.quote(kw)}?type=2&max_results=5', headers=headers, timeout=10)
            if r.status_code == 200 and r.json().get('list'): return[{'id': i['id'], 'name': i.get('name_cn') or i.get('name')} for i in r.json()['list'][:5]]
        except: pass
        return[]

    def search_bangumi(self, keyword):
        if not self.config.get('bangumi_token'): return {'error': '未配置Token'}
        kw_exact = re.sub(r'[\(\)\[\]（）].*?[\(\)\[\]（）]', '', keyword).strip()
        if not kw_exact: kw_exact = keyword
        res = self._do_search(kw_exact)
        if res: return {'results': res}
        
        kw_stripped = re.sub(r'(第\s*\d+\s*(季|章|部)|Season\s*\d+|S\d+|Part\s*\d+|[一二三四五六七八九十壹贰叁肆伍陆柒捌玖拾]+之章)', '', kw_exact, flags=re.IGNORECASE).strip()
        if kw_stripped and kw_stripped != kw_exact:
            res = self._do_search(kw_stripped)
            if res: return {'results': res}
        return {'results':[]}

    def do_sync(self, record):
        try:
            name = record['media_name']
            ep_original = int(record.get('episode_num', 1))
            ep = ep_original
            if name.startswith('视频-'): return {'ok': False, 'error': '无法识别媒体名称'}
            
            search = self.search_bangumi(name)
            if not search.get('results'): return {'ok': False, 'error': '未找到条目'}
            
            initial_sid = search['results'][0]['id']
            subject_name = search['results'][0].get('name')
            headers = {'Authorization': f"Bearer {self.config.get('bangumi_token', '')}", 'Content-Type': 'application/json', 'User-Agent': 'fn-sync/3.0'}
            
            current_sid = initial_sid
            target_ep = None
            
            # 开启最高 4 季的无限续集穿透检索
            for _ in range(4):
                eps =[]; offset = 0
                while True:
                    r = requests.get('https://api.bgm.tv/v0/episodes', headers=headers, params={'subject_id': current_sid, 'limit': 100, 'offset': offset}, timeout=10)
                    if r.status_code != 200: break
                    data = r.json().get('data',[])
                    if not data: break
                    eps.extend(data)
                    if len(data) < 100: break
                    offset += 100
                    
                main_eps = [e for e in eps if e.get('type') == 0]
                # 双重匹配黑科技：既匹配飞牛绝对集数(如13)，也匹配换算后的相对集数(如第2季的1)
                target_ep = next((e for e in main_eps if e.get('ep') == ep or e.get('sort') == ep or e.get('ep') == ep_original or e.get('sort') == ep_original), None)
                if target_ep: break
                
                # 当前季没找到？立刻召唤 Bangumi 图谱检索它的“续集”！
                r_rel = requests.get(f'https://api.bgm.tv/v0/subjects/{current_sid}/subjects', headers=headers, timeout=10)
                if r_rel.status_code != 200: break
                relations = r_rel.json()
                
                sequel = next((rel for rel in relations if rel.get('relation') == '续集'), None)
                if not sequel: break
                
                # 动态计算溢出集数 (13 - 本季12 = 找下一季第1集)
                if len(main_eps) > 0: ep = ep - len(main_eps)
                current_sid = sequel.get('id') or sequel.get('subject_id')
                subject_name = sequel.get('name') or sequel.get('name_cn') or subject_name
            
            if not target_ep: return {'ok': False, 'error': f'包含续集在内均无第{ep_original}集'}
            
            epid = target_ep['id']
            r = requests.put(f'https://api.bgm.tv/v0/users/-/collections/-/episodes/{epid}', headers=headers, json={'type': 2}, timeout=10)
            
            # 动态 400 兜底：准确把查找到的那一季加入在看库
            if r.status_code == 400:
                requests.post(f'https://api.bgm.tv/v0/users/-/collections/{current_sid}', headers=headers, json={'type': 3}, timeout=10)
                r = requests.put(f'https://api.bgm.tv/v0/users/-/collections/-/episodes/{epid}', headers=headers, json={'type': 2}, timeout=10)
                
            if r.status_code in[200, 204]: return {'ok': True, 'name': subject_name}
            return {'ok': False, 'error': f'标记失败(HTTP {r.status_code})'}
        except Exception as e: return {'ok': False, 'error': str(e)}
    
    def run_sync(self, user_guid=None, time_range=None):
        if self.syncing: return {'error': '同步中'}
        self.syncing = True; self.log('=== 开始同步 ===')
        try:
            records = self.get_records(user_guid=user_guid, time_range=time_range, limit=100).get('records', [])
            pending =[r for r in records if r['status'] == '已看完' and f"{r['media_name']}_{r.get('episode_num',1)}" not in self.synced]
            if not pending: self.log('没有待同步记录'); return {'count': 0}
            ok = fail = 0
            for i, r in enumerate(pending, 1):
                if self._stop.is_set(): break
                self.log(f'[{i}/{len(pending)}] {r["media_name"]} (第{r["episode_num"]}集)')
                res = self.do_sync(r)
                if res['ok']: self.log(f' ✓ {res["name"]}'); ok += 1; self.synced.append(f"{r['media_name']}_{r.get('episode_num',1)}"); self.save_cache()
                else: self.log(f' ✗ {res["error"]}'); fail += 1
                time.sleep(1)
            self.last_sync_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            self.log(f'同步完成：成功 {ok}，失败 {fail}')
            return {'count': len(pending), 'success': ok, 'fail': fail}
        finally:
            self.syncing = False; self._stop.clear()

manager = SyncManager()

@app.route('/')
def index(): return render_template('index.html', config=manager.config), 200, {'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0'}
@app.route('/api/config', methods=['GET', 'POST'])
def config():
    if request.method == 'POST': manager.save_config(request.json); return jsonify({'ok': True})
    return jsonify(manager.config)
@app.route('/api/users')
def get_users_api(): return jsonify({'success': True, 'data': manager.get_users()})
@app.route('/api/records')
def records(): return jsonify(manager.get_records(request.args.get('user', 'all'), request.args.get('range', 'all'), 50))
@app.route('/api/search')
def search(): return jsonify(manager.search_bangumi(request.args.get('q', '')))
@app.route('/api/sync/reset', methods=['POST'])
def reset_sync():
    manager.synced =[]
    manager.save_cache()
    manager.log('✅ 已手动清空本地同步记忆库')
    return jsonify({'ok': True})

@app.route('/api/sync', methods=['POST'])
def sync(): 
    data = request.json or {}
    threading.Thread(target=manager.run_sync, kwargs={'user_guid': data.get('user', 'all'), 'time_range': data.get('range', 'all')}, daemon=True).start()
    return jsonify({'ok': True})
@app.route('/api/stop', methods=['POST'])
def stop(): manager._stop.set(); return jsonify({'ok': True})
@app.route('/api/sync/status')
def sync_status(): return jsonify(manager.get_sync_status())
@app.route('/api/sync/mode', methods=['POST'])
def set_sync_mode():
    manager.save_config({'sync_mode': request.json.get('mode', 'manual'), 'sync_interval': request.json.get('interval', 300)})
    return jsonify({'ok': True})
@app.route('/api/status')
def status(): return jsonify({'syncing': manager.syncing, 'db_ok': os.path.exists(DB_PATH)})
@app.route('/api/logs/history')
def logs_history(): return jsonify(manager.last_log)
@app.route('/api/logs')
def logs():
    def gen():
        while True:
            try: yield f'data: {LOG_QUEUE.get(timeout=1)}\n\n'
            except: yield 'data: \n\n'
    return Response(gen(), mimetype='text/event-stream')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, threaded=True)
