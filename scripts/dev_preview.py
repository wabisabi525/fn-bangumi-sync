#!/usr/bin/env python3
"""Run a safe local WebUI preview with mock data and no NAS/Bangumi access."""
import os
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))


def run_preview():
    with tempfile.TemporaryDirectory(prefix='fn-bangumi-sync-preview-') as temp_dir:
        os.chdir(temp_dir)
        os.environ['DB_PATH'] = str(Path(temp_dir) / 'preview.db')

        import app as app_module

        manager = app_module.manager
        manager.config.update({
            'bangumi_token': '',
            'min_percent': 80,
            'user_filter': 'all',
            'time_range': 'all',
            'sync_mode': 'manual',
            'sync_interval': 300,
            'auto_start_on_boot': False,
        })
        manager.last_log = [
            '[预览] 已启动安全的本地 WebUI 环境',
            '[预览] 使用模拟播放记录，不连接飞牛 NAS',
            '[预览] 未加载任何真实 Bangumi Token',
        ]
        manager.get_users = lambda: [
            {'id': 'demo-user', 'name': '演示用户'},
            {'id': 'family-user', 'name': '家庭成员'},
        ]
        manager.get_records = lambda user_guid=None, time_range=None, limit=50: {
            'records': [
                {'media_name': '葬送的芙莉莲', 'episode_title': '再会', 'episode_num': 12, 'play_time': '2026-07-12 20:18', 'percent': 100.0, 'status': '已看完'},
                {'media_name': '迷宫饭', 'episode_title': '炎龙', 'episode_num': 8, 'play_time': '2026-07-11 22:35', 'percent': 87.4, 'status': '已看完'},
                {'media_name': '跃动青春', 'episode_title': '闪闪发光', 'episode_num': 5, 'play_time': '2026-07-10 19:42', 'percent': 46.8, 'status': '观看中'},
                {'media_name': '孤独摇滚！', 'episode_title': '吉他与孤独与蓝色星球', 'episode_num': 3, 'play_time': '2026-07-09 21:06', 'percent': 12.5, 'status': '观看中'},
            ][:limit],
            'count': 4,
            'pending_count': 2,
            'filter': {'user': user_guid or 'all', 'range': time_range or 'all'},
        }

        print('安全预览已启动：http://127.0.0.1:5055')
        print('按 Ctrl+C 停止。所有预览配置都保存在临时目录，退出后自动删除。')
        app_module.app.run(host='127.0.0.1', port=5055, threaded=True, use_reloader=False)


if __name__ == '__main__':
    run_preview()
