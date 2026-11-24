# SPDX-License-Identifier: MIT
import copy
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from run_local_benchmarks import latency_gate

class LatencyGateTests(unittest.TestCase):
    def setUp(self):
        timing = {'samples':100,'p95':12.0}
        self.report = {'iterations':100,'full_decoder_tested':True,'full_decoder':{'cases':[
            {'width':w,'height':h,'budget_mbps':b,'zero_frame':False,
             'decode_gpu_ms':copy.deepcopy(timing),'ready_wall_ms':copy.deepcopy(timing)}
            for w,h in [(1280,720),(1920,1080),(3840,2160)] for b in [150,300,500,1000]]}}

    def test_complete_measurement_passes(self):
        self.assertTrue(latency_gate(self.report,50)['passed'])

    def test_gpu_timestamp_alone_cannot_pass(self):
        self.report['full_decoder']['cases'][0]['ready_wall_ms']['p95']=70
        self.assertFalse(latency_gate(self.report,50)['passed'])

    def test_missing_profile_fails(self):
        self.report['full_decoder']['cases'].pop()
        self.assertFalse(latency_gate(self.report,50)['passed'])

    def test_incomplete_or_invalid_timing_fails(self):
        for value in [None,{'samples':99,'p95':1}, {'samples':100,'p95':float('nan')},
                      {'samples':100,'p95':50}, {'samples':100,'p95':0}]:
            with self.subTest(value=value):
                self.report['full_decoder']['cases'][0]['decode_gpu_ms']=value
                self.assertFalse(latency_gate(self.report,50)['passed'])

    def test_short_run_fails(self):
        self.report['iterations']=8
        self.assertFalse(latency_gate(self.report,50)['passed'])
