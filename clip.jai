/*
    Uniformly sampled, local-space skeletal animation. Sample i occurs at i / sample_rate seconds.
    The last sample is an endpoint: duration is (num_samples - 1) / sample_rate. Looping clips should
    repeat their starting pose at that endpoint for a seamless loop. A single-sample clip is static.
    Channels contain zero keys (use the skeleton default), one constant key, or num_samples keys.
    Clip owns its dynamic arrays; do not shallow-copy ownership. Bind once after loading, then keep
    clip/skeleton data and addresses stable while using the Binding. Sampling and playback allocate
    no memory. Player is independent so multiple instances can share one immutable clip/binding.
*/
KeyTemplate :: struct (Value_Type: Type) {
    value: Value_Type;
}

KeyFloat :: KeyTemplate(float);
KeyVec3 :: KeyTemplate(Math.Vec3);
KeyQuat :: KeyTemplate(Math.Quat);

BoneTrack :: struct {
    bone: Name;
    positions: [..]KeyVec3;
    rotations: [..]KeyQuat;
    scales: [..]KeyFloat;
}

Clip :: struct {
    name: Name;
    sample_rate: float = 30.0;
    num_samples: u32;
    tracks: [..]BoneTrack;
}

Binding :: struct {
    clip: *Clip;
    skeleton: *Skeleton;
    bone_indices: [MAX_BONE_COUNT]u8;
    num_tracks: int;
}

clip_duration :: (clip: *Clip) -> float {
    Basic.assert(clip.num_samples > 0 && Math.is_finite(clip.sample_rate) && clip.sample_rate > 0.0);
    return cast(float) (clip.num_samples - 1) / clip.sample_rate;
}

// Always validates metadata and channel sizes. Loaders pass true to also check every key value.
// Full checks require finite values and normalized, nonzero quaternions. Binding uses false.
validate_clip :: (clip: *Clip, full_check: bool) -> bool {
    if (!clip || clip.num_samples == 0 || !Math.is_finite(clip.sample_rate) ||
        clip.sample_rate <= 0.0 || clip.tracks.count > MAX_BONE_COUNT) {
        return false;
    }

    if !Math.is_finite(clip_duration(clip)) {
        return false;
    }

    for track: clip.tracks {
        if (!valid_channel_count(track.positions.count, clip.num_samples) ||
            !valid_channel_count(track.rotations.count, clip.num_samples) ||
            !valid_channel_count(track.scales.count, clip.num_samples)) {
            return false;
        }

        if !full_check {
            continue;
        }

        for key: track.positions {
            if !Math.is_finite(key.value.x) || !Math.is_finite(key.value.y) || !Math.is_finite(key.value.z) {
                return false;
            }
        }

        for key: track.rotations {
            norm := Math.dot(key.value, key.value);
            if !Math.is_finite(norm) || Math.abs(norm - 1.0) > 0.0001 {
                return false;
            }
        }

        for key: track.scales {
            if !Math.is_finite(key.value) {
                return false;
            }
        }
    }
    return true;
}

// Missing/duplicate targets fail atomically: the previous binding remains unchanged.
bind_animation :: (clip: *Clip, skeleton: *Skeleton, binding: *Binding) -> bool {
    if !clip {
        Basic.assert(false, "Cannot bind animation: clip is null.");
        return false;
    }
    if !skeleton {
        Basic.assert(false, "Cannot bind animation: skeleton is null.");
        return false;
    }
    if !binding {
        Basic.assert(false, "Cannot bind animation: output binding is null.");
        return false;
    }
    if !validate_clip(clip, false) {
        Basic.assert(false, "Cannot bind animation '%': invalid clip metadata or channel sizes.", clip.name.text);
        return false;
    }

    if skeleton.num_bones > MAX_BONE_COUNT {
        Basic.assert(false, "Cannot bind animation: skeleton has % bones, maximum is %.", skeleton.num_bones, MAX_BONE_COUNT);
        return false;
    }
    if skeleton.default_pose.num_bones != skeleton.num_bones {
        Basic.assert(false, "Cannot bind animation: default pose has % bones, skeleton has %.",
                     skeleton.default_pose.num_bones, skeleton.num_bones);
        return false;
    }

    result: Binding;
    result.clip = clip;
    result.skeleton = skeleton;
    result.num_tracks = clip.tracks.count;
    used: [MAX_BONE_COUNT]bool;
    for track, index: clip.tracks {
        found, bone := ClipTables.table_find(*skeleton.bone_mapping.table, track.bone);
        if !found {
            Basic.assert(false, "Cannot bind animation: track % targets missing bone '%'.", index, track.bone.text);
            return false;
        }
        if bone >= skeleton.num_bones {
            Basic.assert(false, "Cannot bind animation: bone '%' maps to index %, skeleton has % bones.",
                         track.bone.text, bone, skeleton.num_bones);
            return false;
        }
        
        if used[bone] {
            Basic.assert(false, "Cannot bind animation: track % duplicates target bone '%' (index %).", index, track.bone.text, bone);
            return false;
        }
        used[bone] = true;
        result.bone_indices[index] = bone;
    }

    binding.* = result;
    return true;
}

// Time is clamped to clip endpoints. Loop wrapping belongs to Player, not to sampling.
sample_animation :: (binding: *Binding, time: float, result: *Pose) {
    Basic.assert(binding.clip != null && binding.skeleton != null && Math.is_finite(time));

    clip := binding.clip;
    Basic.assert(binding.num_tracks == clip.tracks.count);

    position := Basic.clamp(time, 0.0, clip_duration(clip)) * clip.sample_rate;
    position = Basic.min(position, cast(float) (clip.num_samples - 1));

    // Float rounding can put a large endpoint just beyond the final integer sample index.
    first := Basic.min(cast(int) position, cast(int) clip.num_samples - 1);
    second := Basic.min(first + 1, cast(int) clip.num_samples - 1);
    fraction := position - cast(float) first;

    result.* = binding.skeleton.default_pose;
    for track, index: clip.tracks {
        transform := *result.bone_transforms[binding.bone_indices[index]];

        if track.positions.count > 0 {
            a, b := channel_indices(track.positions.count, first, second);
            transform.position = Math.lerp(track.positions[a].value, track.positions[b].value, fraction);
        }

        if track.rotations.count > 0 {
            a, b := channel_indices(track.rotations.count, first, second);
            transform.rotation = Math.slerp_unclamped(track.rotations[a].value, track.rotations[b].value, fraction);
        }

        if track.scales.count > 0 {
            a, b := channel_indices(track.scales.count, first, second);
            transform.scale = Math.lerp(track.scales[a].value, track.scales[b].value, fraction);
        }
    }
}

// Invalidates bindings to this clip. Free with the allocator that owns its arrays.
free_clip :: (clip: *Clip) {
    for track: clip.tracks {
        Basic.array_free(track.positions);
        Basic.array_free(track.rotations);
        Basic.array_free(track.scales);
    }
    Basic.array_free(clip.tracks);
    clip.* = .{};
}

#scope_file
ClipTables :: #import "Hash_Table";

valid_channel_count :: (count: int, samples: u32) -> bool {
    return count == 0 || count == 1 || count == samples;
}

channel_indices :: (count: int, first: int, second: int) -> (int, int) {
    if count == 1 {
        return 0, 0;
    }
    return first, second;
}
