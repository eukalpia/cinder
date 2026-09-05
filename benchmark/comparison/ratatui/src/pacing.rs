use std::time::{Duration, Instant};

#[derive(Debug, PartialEq)]
pub enum Action {
    Draw,
    ReadInput(Option<Duration>),
}

pub struct FrameSchedule {
    interval: Duration,
    next_frame: Instant,
    dirty: bool,
}

impl FrameSchedule {
    pub fn new(interval: Duration, now: Instant) -> Self {
        Self {
            interval,
            next_frame: now,
            dirty: true,
        }
    }

    pub fn next_action(&self, now: Instant) -> Action {
        if !self.dirty {
            Action::ReadInput(None)
        } else if now >= self.next_frame {
            Action::Draw
        } else {
            Action::ReadInput(Some(self.next_frame - now))
        }
    }

    pub fn drawn(&mut self, started_at: Instant) {
        self.next_frame = started_at + self.interval;
        self.dirty = false;
    }

    pub fn changed(&mut self) {
        self.dirty = true;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn queued_input_can_be_read_between_capped_draws() {
        let start = Instant::now();
        let period = Duration::from_millis(20);
        let mut schedule = FrameSchedule::new(period, start);
        assert_eq!(schedule.next_action(start), Action::Draw);
        schedule.drawn(start);
        assert_eq!(schedule.next_action(start), Action::ReadInput(None));

        for milliseconds in [1, 4, 8, 12, 16] {
            let elapsed = Duration::from_millis(milliseconds);
            schedule.changed();
            assert_eq!(
                schedule.next_action(start + elapsed),
                Action::ReadInput(Some(period - elapsed)),
            );
        }
        assert_eq!(schedule.next_action(start + period), Action::Draw);
    }

    #[test]
    fn coalesced_changes_do_not_postpone_the_pending_draw() {
        let start = Instant::now();
        let period = Duration::from_millis(20);
        let mut schedule = FrameSchedule::new(period, start);
        schedule.drawn(start);
        for _ in 0..192 {
            schedule.changed();
        }
        assert_eq!(schedule.next_action(start + period), Action::Draw);
        let delayed_start = start + period * 2;
        schedule.drawn(delayed_start);
        schedule.changed();
        assert_eq!(
            schedule.next_action(delayed_start),
            Action::ReadInput(Some(period)),
        );
    }
}
