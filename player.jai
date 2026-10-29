// Per-instance playback time, speed and looping policy for shared animation clips.
// Time and delta_time are in seconds. Advancing playback does not allocate or sample a pose.

PlaybackMode :: enum {
    Once;
    Loop;
}

Player :: struct {
    time: float;
    speed: float = 1.0;
    mode: PlaybackMode = .Loop;
    playing: bool;
}

// Negative speed supports reverse playback. Once stops at the endpoint reached in that direction.
advance_animation :: (player: *Player, clip: *Clip, delta_time: float) {
    Basic.assert(Math.is_finite(delta_time) && delta_time >= 0.0);
    Basic.assert(Math.is_finite(player.time) && Math.is_finite(player.speed));

    if !player.playing {
        return;
    }

    duration := clip_duration(clip);
    if duration == 0.0 {
        player.time = 0.0;
        if player.mode == .Once {
            player.playing = false;
        }
        return;
    }

    next := player.time + delta_time * player.speed;
    if player.mode == .Loop {
        cycles := next / duration;
        next -= Math.floor(cycles) * duration;
        if next < 0.0 {
            next += duration;
        }

        if next >= duration {
            next = 0.0;
        }

        player.time = next;
    }
    else {
        player.time = Basic.clamp(next, 0.0, duration);
        if (delta_time > 0.0 &&
            ((player.speed > 0.0 && next >= duration) || (player.speed < 0.0 && next <= 0.0))) {
            player.playing = false;
        }
    }
}

