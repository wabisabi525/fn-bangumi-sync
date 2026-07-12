import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import app as app_module


class SyncManagerStartupTests(unittest.TestCase):
    def base_config(self, **overrides):
        config = {
            'bangumi_token': '',
            'min_percent': 80,
            'user_filter': 'all',
            'time_range': 'all',
            'sync_mode': 'manual',
            'sync_interval': 300,
            'auto_start_on_boot': False,
        }
        config.update(overrides)
        return config

    def test_missing_boot_field_defaults_to_manual_without_scheduler(self):
        config = self.base_config(sync_mode='auto')
        config.pop('auto_start_on_boot')
        with patch.object(app_module.SyncManager, 'load_config', return_value=config),              patch.object(app_module.SyncManager, 'load_cache', return_value=[]),              patch.object(app_module.SyncManager, 'start_auto_sync') as start_auto_sync:
            manager = app_module.SyncManager()

        self.assertEqual(manager.config['sync_mode'], 'manual')
        self.assertFalse(manager.config.get('auto_start_on_boot', False))
        start_auto_sync.assert_not_called()

    def test_explicit_false_stays_manual_without_scheduler(self):
        config = self.base_config(sync_mode='auto', auto_start_on_boot=False)
        with patch.object(app_module.SyncManager, 'load_config', return_value=config),              patch.object(app_module.SyncManager, 'load_cache', return_value=[]),              patch.object(app_module.SyncManager, 'start_auto_sync') as start_auto_sync:
            manager = app_module.SyncManager()

        self.assertEqual(manager.config['sync_mode'], 'manual')
        start_auto_sync.assert_not_called()

    def test_true_starts_scheduler_with_saved_interval(self):
        captured_intervals = []

        def capture_start(manager):
            captured_intervals.append(manager.config['sync_interval'])
            manager.scheduler_job = object()
            return True

        config = self.base_config(sync_mode='manual', sync_interval=900, auto_start_on_boot=True)
        with patch.object(app_module.SyncManager, 'load_config', return_value=config),              patch.object(app_module.SyncManager, 'load_cache', return_value=[]),              patch.object(app_module.SyncManager, 'start_auto_sync', capture_start):
            manager = app_module.SyncManager()

        self.assertEqual(manager.config['sync_mode'], 'auto')
        self.assertEqual(captured_intervals, [900])
        self.assertIsNotNone(manager.scheduler_job)

    def test_default_config_contains_disabled_boot_flag(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            missing_config = str(Path(temp_dir) / 'config.json')
            with patch.object(app_module, 'CONFIG_FILE', missing_config):
                manager = app_module.SyncManager()

        self.assertFalse(manager.config['auto_start_on_boot'])
        self.assertEqual(manager.config['sync_mode'], 'manual')
        self.assertIsNone(manager.scheduler_job)


class SyncModeApiTests(unittest.TestCase):
    def setUp(self):
        self.client = app_module.app.test_client()

    def test_legacy_auto_request_enables_boot_start(self):
        with patch.object(app_module.manager, 'save_config') as save_config:
            response = self.client.post('/api/sync/mode', json={'mode': 'auto', 'interval': 300})

        self.assertEqual(response.status_code, 200)
        save_config.assert_called_once_with({
            'sync_mode': 'auto',
            'sync_interval': 300,
            'auto_start_on_boot': True,
        })

    def test_explicit_disabled_boot_start_forces_manual_mode(self):
        with patch.object(app_module.manager, 'save_config') as save_config:
            response = self.client.post('/api/sync/mode', json={
                'mode': 'auto',
                'interval': 60,
                'auto_start_on_boot': False,
            })

        self.assertEqual(response.status_code, 200)
        save_config.assert_called_once_with({
            'sync_mode': 'manual',
            'sync_interval': 60,
            'auto_start_on_boot': False,
        })

    def test_explicit_enabled_boot_start_forces_auto_mode(self):
        with patch.object(app_module.manager, 'save_config') as save_config:
            response = self.client.post('/api/sync/mode', json={
                'mode': 'manual',
                'interval': 3600,
                'auto_start_on_boot': True,
            })

        self.assertEqual(response.status_code, 200)
        save_config.assert_called_once_with({
            'sync_mode': 'auto',
            'sync_interval': 3600,
            'auto_start_on_boot': True,
        })


class WebUiContractTests(unittest.TestCase):
    def test_template_contains_linked_boot_switch(self):
        template = Path(__file__).resolve().parents[1] / 'templates' / 'index.html'
        html = template.read_text(encoding='utf-8')

        self.assertIn('id="autoStartOnBoot"', html)
        self.assertIn("updateSyncMode('boot')", html)
        self.assertIn('auto_start_on_boot:bootToggle.checked', html)
        self.assertIn("updateSyncMode('mode')", html)
        self.assertIn('class="workspace-sidebar"', html)
        self.assertIn('<h1>飞牛番组管家</h1>', html)
        self.assertIn('自动同步观看记录 | 飞牛影视 → Bangumi', html)
        self.assertNotIn('FN Bangumi Sync', html)
        self.assertIn('id="sidebarToggle"', html)
        self.assertIn('function toggleSidebar()', html)
        self.assertIn('id="bangumiPage" hidden', html)
        self.assertIn('data-view="bangumi"', html)
        self.assertNotIn('href="#logs-panel"', html)
        self.assertIn('id="logs-panel"', html)
        self.assertIn('bootstrap-icons.min.css', html)
        self.assertIn('bi bi-grid-1x2-fill nav-icon', html)
        self.assertIn('data-view="sync"', html)
        self.assertIn('id="syncPage" hidden', html)
        self.assertNotIn('data-short=', html)
        self.assertNotIn('episode_title', html)
        self.assertLess(html.index('id="filter-settings"'), html.index('id="logs-panel"'))


if __name__ == '__main__':
    unittest.main()
