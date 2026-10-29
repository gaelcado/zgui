//! A call's two voices made up, for sample data and previews: whoever is
//! said to speak talks in words of about two a second, syllables at
//! Zeron's preview pace (4.7 a second), and each voice's loudness is split
//! into its bands as Codex's is in a real call ([`Rhythm`]). Nothing but
//! the frames' times moves it, so it plays the same at any speed.
use super::glyph::{Rhythm, Voice};
use std::{f32::consts::TAU, time::Instant};

/// Who speaks in a sample call.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Speaker {
    /// No one: both voices fall quiet.
    #[default]
    Nobody,
    /// The user.
    User,
    /// Codex.
    Agent,
}

/// Seconds a word takes, and the share of it the voice holds before the
/// gap to the next.
const WORD: f32 = 0.42;
/// Syllables a second inside the words (the preview's `4.7`).
const SYLLABLES: f32 = 4.7;
/// Seconds a voice takes to rise as its turn begins and to fall as it ends.
const ATTACK: f32 = 0.08;
const RELEASE: f32 = 0.2;
/// The loudest peak said, as the preview's half scale.
const PEAK: f32 = 0.5;

/// One made-up voice: its loudness's envelope, the time into its turn, and
/// its bands.
#[derive(Default)]
struct Talker {
    on: f32,
    into: f32,
    rhythm: Rhythm,
}

impl Talker {
    fn hear(&mut self, speaking: bool, dt: f32, now: Instant) {
        let pace = if speaking { ATTACK } else { RELEASE };
        let target = if speaking { 1.0 } else { 0.0 };
        self.on += (target - self.on) * (1.0 - (-dt / pace).exp());
        if self.on < 1e-3 && !speaking {
            self.on = 0.0;
            self.into = 0.0;
        } else {
            self.into += dt;
        }
        self.rhythm.hear(PEAK * self.on * peak(self.into), now);
    }
}

/// The loudness, 0–1, of a voice `t` seconds into its turn: each word
/// swells and falls back, some louder than others, and the syllables beat
/// inside them.
fn peak(t: f32) -> f32 {
    let word = (t / WORD).floor();
    let into = (t / WORD).fract();
    // Some words carry more than others, the same ones every time.
    let stress = 0.7 + 0.3 * hash(word);
    let swell = (into * std::f32::consts::PI).sin().max(0.0).powf(0.5);
    let syllable = (t * SYLLABLES * TAU).sin().max(0.0).powf(1.4);
    stress * swell * (0.2 + 0.8 * syllable)
}

fn hash(n: f32) -> f32 {
    let mut h = (n as i32 as u32).wrapping_mul(0x9E37_79B1);
    h ^= h >> 15;
    h = h.wrapping_mul(0x2C1B_3C6D);
    h ^= h >> 12;
    (h % 1000) as f32 / 999.0
}

/// The two voices of a sample call.
#[derive(Default)]
pub struct SampleSpeech {
    speaker: Speaker,
    user: Talker,
    agent: Talker,
    at: Option<Instant>,
}

impl SampleSpeech {
    /// `speaker` talks from now on.
    pub fn speak(&mut self, speaker: Speaker) {
        self.speaker = speaker;
    }

    /// Who talks.
    pub fn speaker(&self) -> Speaker {
        self.speaker
    }

    /// Both voices at `now`, band by band.
    pub fn hear(&mut self, now: Instant) -> Voice {
        let dt = self
            .at
            .replace(now)
            .map_or(0.0, |at| now.saturating_duration_since(at).as_secs_f32())
            .min(0.25);
        self.user.hear(self.speaker == Speaker::User, dt, now);
        self.agent.hear(self.speaker == Speaker::Agent, dt, now);
        Voice {
            user: self.user.rhythm.bands(),
            agent: self.agent.rhythm.bands(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn loudest(voice: &[f32]) -> f32 {
        voice.iter().copied().fold(0.0, f32::max)
    }

    #[test]
    fn whoever_speaks_moves_their_own_voice_alone_and_falls_quiet_after() {
        let start = Instant::now();
        let mut speech = SampleSpeech::default();
        let at = |ms: u64| start + Duration::from_millis(ms);
        speech.speak(Speaker::Agent);
        let (mut agent, mut user, mut low) = (0.0f32, 0.0f32, 1.0f32);
        for frame in 0..90u64 {
            let voice = speech.hear(at(frame * 33));
            if frame > 10 {
                agent = agent.max(loudest(&voice.agent));
                low = low.min(voice.agent[4]);
            }
            user = user.max(loudest(&voice.user));
        }
        assert!(agent > 0.6, "Codex speaks: {agent}");
        assert!(low < agent * 0.5, "its quick bands move: {low}");
        assert_eq!(user, 0.0, "the user is silent");
        speech.speak(Speaker::User);
        let mut user = 0.0f32;
        for frame in 90..150u64 {
            user = user.max(loudest(&speech.hear(at(frame * 33)).user));
        }
        assert!(user > 0.6, "the user speaks: {user}");
        speech.speak(Speaker::Nobody);
        let mut voice = Voice::default();
        for frame in 150..240u64 {
            voice = speech.hear(at(frame * 33));
        }
        assert!(loudest(&voice.user) < 0.02 && loudest(&voice.agent) < 0.02);
    }

    #[test]
    fn the_same_frames_hear_the_same_voice() {
        let start = Instant::now();
        let run = || {
            let mut speech = SampleSpeech::default();
            speech.speak(Speaker::User);
            (0..40u64)
                .map(|frame| speech.hear(start + Duration::from_millis(frame * 33)))
                .collect::<Vec<_>>()
        };
        assert_eq!(run(), run());
    }
}
