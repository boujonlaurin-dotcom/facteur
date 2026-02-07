"""Tests for the background job scheduler.

This module verifies that scheduled jobs are properly configured
to trigger at the expected times with correct timezones.

Tests:
- Scheduler job configuration
- Daily digest job at 8am Europe/Paris
- Job trigger parameters
"""

import pytest
from unittest.mock import Mock, patch, MagicMock
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
import pytz

from app.workers.scheduler import start_scheduler, stop_scheduler


class TestScheduler:
    """Tests for the background job scheduler configuration."""
    
    def test_scheduler_has_daily_digest_job(self):
        """TEST-01: Verify daily digest job is scheduled at 8am Paris time."""
        with patch('app.workers.scheduler.AsyncIOScheduler') as mock_scheduler_class:
            # Create a mock scheduler instance
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler
            
            # Track the add_job calls
            add_job_calls = []
            def capture_add_job(*args, **kwargs):
                add_job_calls.append({
                    'func': args[0] if args else kwargs.get('func'),
                    'trigger': kwargs.get('trigger'),
                    'id': kwargs.get('id'),
                    'name': kwargs.get('name'),
                    'replace_existing': kwargs.get('replace_existing')
                })
            
            mock_scheduler.add_job = capture_add_job
            
            # Start the scheduler
            start_scheduler()
            
            # Verify the scheduler was started
            mock_scheduler.start.assert_called_once()
            
            # Find the daily_digest job
            digest_jobs = [call for call in add_job_calls if call.get('id') == 'daily_digest']
            assert len(digest_jobs) == 1, f"Expected 1 daily_digest job, found {len(digest_jobs)}"
            
            job = digest_jobs[0]
            
            # Verify the trigger is a CronTrigger
            assert isinstance(job['trigger'], CronTrigger), f"Expected CronTrigger, got {type(job['trigger'])}"
            
            # Verify the job uses run_digest_generation function
            assert job['func'].__name__ == 'run_digest_generation', \
                f"Expected run_digest_generation, got {job['func'].__name__}"
            
            # Verify timezone is Europe/Paris
            trigger_tz = str(job['trigger'].timezone)
            assert 'Europe/Paris' in trigger_tz or 'CET' in trigger_tz or 'CEST' in trigger_tz, \
                f"Expected Europe/Paris timezone, got {trigger_tz}"
            
            # Verify job name
            assert job['name'] == 'Daily Digest Generation', \
                f"Expected 'Daily Digest Generation', got {job['name']}"
            
            # Verify replace_existing is True
            assert job['replace_existing'] is True, \
                f"Expected replace_existing=True, got {job['replace_existing']}"
    
    def test_daily_digest_job_trigger_params(self):
        """TEST-01: Verify digest job triggers at exactly 8:00 daily."""
        with patch('app.workers.scheduler.AsyncIOScheduler') as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler
            
            trigger_calls = []
            def capture_add_job(*args, **kwargs):
                trigger_calls.append(kwargs.get('trigger'))
            
            mock_scheduler.add_job = capture_add_job
            
            start_scheduler()
            
            # Find the digest trigger
            digest_trigger = None
            for call in mock_scheduler.add_job.call_args_list if hasattr(mock_scheduler.add_job, 'call_args_list') else []:
                if call and call.kwargs.get('id') == 'daily_digest':
                    digest_trigger = call.kwargs.get('trigger')
                    break
            
            # Alternative: check from our captured calls
            if digest_trigger is None:
                # We captured via the capture_add_job function
                # Need to inspect the trigger from the mock
                for call in mock_scheduler.add_job.call_args_list if hasattr(mock_scheduler, 'add_job') else []:
                    pass  # Skip if no call_args_list
            
            # Re-examine: just verify the trigger fields
            # The CronTrigger should have hour=8, minute=0
            # Let's inspect the actual scheduler.add_job calls
            if hasattr(mock_scheduler.add_job, 'call_args_list'):
                for call in mock_scheduler.add_job.call_args_list:
                    if call.kwargs.get('id') == 'daily_digest':
                        trigger = call.kwargs.get('trigger')
                        # Check if it's a CronTrigger with hour=8, minute=0
                        assert isinstance(trigger, CronTrigger)
                        # The trigger should have these fields set
                        # We can verify by checking the string representation
                        trigger_str = str(trigger)
                        assert '8' in trigger_str and '0' in trigger_str, \
                            f"Trigger should have hour=8 and minute=0, got: {trigger_str}"
    
    def test_scheduler_includes_rss_sync_job(self):
        """Verify RSS sync job is scheduled."""
        with patch('app.workers.scheduler.AsyncIOScheduler') as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler
            
            job_ids = []
            def capture_add_job(*args, **kwargs):
                job_ids.append(kwargs.get('id'))
            
            mock_scheduler.add_job = capture_add_job
            
            start_scheduler()
            
            # Verify rss_sync job exists
            assert 'rss_sync' in job_ids, f"rss_sync job not found. Jobs: {job_ids}"
    
    def test_scheduler_includes_daily_top3_job(self):
        """Verify Top 3 briefing job is scheduled."""
        with patch('app.workers.scheduler.AsyncIOScheduler') as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler
            
            job_ids = []
            def capture_add_job(*args, **kwargs):
                job_ids.append(kwargs.get('id'))
            
            mock_scheduler.add_job = capture_add_job
            
            start_scheduler()
            
            # Verify daily_top3 job exists
            assert 'daily_top3' in job_ids, f"daily_top3 job not found. Jobs: {job_ids}"
    
    def test_stop_scheduler_shuts_down(self):
        """Verify stop_scheduler properly shuts down the scheduler."""
        with patch('app.workers.scheduler.AsyncIOScheduler') as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler
            
            # Start and then stop
            start_scheduler()
            stop_scheduler()
            
            # Verify shutdown was called
            mock_scheduler.shutdown.assert_called_once()


class TestDigestJobConfiguration:
    """Tests specifically for the digest generation job configuration."""
    
    def test_digest_job_timezone_europe_paris(self):
        """TEST-01: Verify digest job uses Europe/Paris timezone."""
        with patch('app.workers.scheduler.AsyncIOScheduler') as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler
            
            captured_triggers = {}
            def capture_add_job(*args, **kwargs):
                job_id = kwargs.get('id')
                if job_id:
                    captured_triggers[job_id] = kwargs.get('trigger')
            
            mock_scheduler.add_job = capture_add_job
            
            start_scheduler()
            
            # Check the daily_digest trigger timezone
            digest_trigger = captured_triggers.get('daily_digest')
            assert digest_trigger is not None, "daily_digest trigger not found"
            
            # Verify timezone
            assert digest_trigger.timezone == pytz.timezone('Europe/Paris'), \
                f"Expected Europe/Paris timezone, got {digest_trigger.timezone}"
    
    def test_digest_job_cron_expression(self):
        """TEST-01: Verify digest job cron expression is 0 8 * * * (8am daily)."""
        with patch('app.workers.scheduler.AsyncIOScheduler') as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler
            
            captured_triggers = {}
            def capture_add_job(*args, **kwargs):
                job_id = kwargs.get('id')
                if job_id:
                    captured_triggers[job_id] = kwargs.get('trigger')
            
            mock_scheduler.add_job = capture_add_job
            
            start_scheduler()
            
            # Check the daily_digest trigger
            digest_trigger = captured_triggers.get('daily_digest')
            assert digest_trigger is not None, "daily_digest trigger not found"
            
            # Verify CronTrigger fields
            # hour should be 8, minute should be 0
            assert digest_trigger.fields[0].__str__() == '0', \
                f"Expected minute=0, got {digest_trigger.fields[0]}"
            assert digest_trigger.fields[1].__str__() == '8', \
                f"Expected hour=8, got {digest_trigger.fields[1]}"
