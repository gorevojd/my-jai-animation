// Per-instance playback time, speed and looping policy for shared animation clips.
// Time and delta_time are in seconds. Advancing playback does not allocate or sample a pose.
// get_player_pose samples lazily and returns borrowed, read-only storage owned by the Player.
// Keep bindings and source data immutable while cached; invalidate_player_pose after editing/rebinding.

PlaybackMode :: enum {
    Once;
    Loop;
}

PlaybackState :: enum {
    Stopped;
    Playing;
    Paused;
}

Player :: struct {
    time: float;
    speed: float = 1.0;
    mode: PlaybackMode = .Loop;
    state: PlaybackState;

    dirty: bool = true;
    cached_pose: Pose;
    cached_time: float;
    cached_binding: *Binding;
    cached_clip: *Clip;
    cached_skeleton: *Skeleton;
}

// Always restarts; reverse playback begins at the final sample. Use unpause to resume.
play :: (player: *Player, clip: *Clip) {
    Basic.assert(Math.is_finite(player.speed));
    player.time = ifx player.speed < 0.0 then clip_duration(clip) else 0.0;
    player.state = .Playing;
    invalidate_player_pose(player);
}

// Explicit stop resets to the first sample. Natural completion retains the reached endpoint.
stop :: (player: *Player) {
    player.state = .Stopped;
    if player.time != 0.0 {
        player.time = 0.0;
        invalidate_player_pose(player);
    }
}

pause :: (player: *Player) {
    if player.state == .Playing {
        player.state = .Paused;
    }
}

unpause :: (player: *Player) {
    if player.state == .Paused {
        player.state = .Playing;
    }
}

invalidate_player_pose :: (player: *Player) {
    player.dirty = true;
}

get_player_pose :: (player: *Player, binding: *Binding) -> *Pose {
    Basic.assert(binding != null && binding.clip != null && binding.skeleton != null);

    // Also catch direct writes to the public time field and switching source objects.
    if (player.dirty ||
        !equal(player.cached_time, player.time) ||
        player.cached_binding != binding ||
        player.cached_clip != binding.clip ||
        player.cached_skeleton != binding.skeleton)
    {
        sample_animation(binding, player.time, *player.cached_pose);
        player.cached_time = player.time;
        player.cached_binding = binding;
        player.cached_clip = binding.clip;
        player.cached_skeleton = binding.skeleton;
        player.dirty = false;
    }

    return *player.cached_pose;
}

// Negative speed supports reverse playback. Once stops at the endpoint reached in that direction.
advance_animation :: (player: *Player, clip: *Clip, delta_time: float) {
    Basic.assert(Math.is_finite(delta_time) && delta_time >= 0.0);
    Basic.assert(Math.is_finite(player.time) && Math.is_finite(player.speed));

    if player.state != .Playing {
        return;
    }

    previous_time := player.time;
    defer {
        if player.time != previous_time {
            invalidate_player_pose(player);
        }
    }

    duration := clip_duration(clip);
    if duration == 0.0 {
        player.time = 0.0;
        if player.mode == .Once {
            player.state = .Stopped;
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
            player.state = .Stopped;
        }
    }
}

