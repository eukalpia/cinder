"""Behavioral oracle tests for the shared, data-driven terminal workflow."""
import unittest

import data_workload as data


class DataWorkflowTest(unittest.TestCase):
    def test_selection_survives_search_and_sort(self):
        model = data.Workspace(data.workload(120, 40, 60, 1000))
        model.apply('j')
        selected_id = model.matches[model.cursor]['id']
        model.apply('x')
        model.apply('f')
        self.assertTrue(all('needle' in row['message'] for row in model.matches))
        model.apply('s')
        self.assertEqual([r['score'] for r in model.matches],
                         sorted([r['score'] for r in model.matches], reverse=True))
        model.apply('f')
        self.assertIn(selected_id, model.selected)

    def test_virtualized_viewport_and_append_have_exact_content(self):
        model = data.Workspace(data.workload(120, 40, 60, 1000))
        initial = model.lines()
        self.assertEqual(len(initial), 40)
        self.assertTrue(all(len(row) == 120 for row in initial))
        self.assertIn('000000 service-00 INFO', initial[3])
        self.assertNotIn('000999', '\n'.join(initial))
        model.apply('G')
        self.assertEqual(model.cursor, 999)
        self.assertEqual(model.top, 968)
        model.apply('a')
        self.assertEqual(len(model.records), 1001)
        self.assertEqual(model.records[-1], data.record(1000))
        self.assertIn('append', '\n'.join(model.lines()[-5:]))

    def test_every_action_changes_screen_and_matches_are_real(self):
        model = data.Workspace(data.workload(120, 40, 60, 1000))
        previous = model.lines()
        for key in data.ACTIONS * 2:
            model.apply(key)
            current = model.lines()
            self.assertNotEqual(current, previous)
            self.assertEqual(len(current), 40)
            self.assertTrue(all(len(row) == 120 for row in current))
            previous = current
        model.apply('e')
        self.assertTrue(all(r['level'] == 'ERROR' for r in model.matches))

    def test_oracle_states_are_not_supplied_to_adapters(self):
        spec = data.workload(120, 40, 60, 1000)
        self.assertNotIn('frames', spec)
        self.assertEqual(len(spec['records']), 1000)
        self.assertEqual(spec['actions'], list(data.ACTIONS))


if __name__ == '__main__':
    unittest.main()
