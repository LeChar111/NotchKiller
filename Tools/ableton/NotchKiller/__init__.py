# NotchKiller — script d'extension (Remote Script) pour Ableton Live 11 / 12.
#
# Installé par NotchKiller dans « User Library/Remote Scripts/NotchKiller »,
# puis choisi comme « Control Surface » dans Préférences → Link, Tempo & MIDI.
# Toutes les ~100 ms, il envoie l'état du set en JSON (UDP 127.0.0.1:9102) et
# exécute les commandes que NotchKiller lui adresse (UDP 127.0.0.1:9101).
# Le Live Object Model n'est touché que depuis update_display, donc sur le
# fil principal de Live.

from __future__ import absolute_import

import json
import socket

try:
    from ableton.v2.control_surface import ControlSurface
except ImportError:  # Live 10 et antérieurs
    from _Framework.ControlSurface import ControlSurface

VERSION = 1
LISTEN = ("127.0.0.1", 9101)
TARGET = ("127.0.0.1", 9102)
GRID_TRACKS = 8
GRID_SCENES = 8


def create_instance(c_instance):
    return NotchKiller(c_instance)


def _get(obj, name, default=None):
    try:
        return getattr(obj, name)
    except Exception:
        return default


class NotchKiller(ControlSurface):
    def __init__(self, c_instance):
        ControlSurface.__init__(self, c_instance)
        self._track_offset = 0
        self._scene_offset = 0
        self._sock = None
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(LISTEN)
            sock.setblocking(False)
            self._sock = sock
        except Exception as error:
            self.log_message("NotchKiller: socket indisponible (%s)" % error)

    # MARK: Cycle de vie

    def disconnect(self):
        if self._sock is not None:
            try:
                self._sock.close()
            except Exception:
                pass
            self._sock = None
        ControlSurface.disconnect(self)

    def update_display(self):
        ControlSurface.update_display(self)
        if self._sock is None:
            return
        self._receive()
        try:
            payload = json.dumps(self._state(), separators=(",", ":"))
            self._sock.sendto(payload.encode("utf-8"), TARGET)
        except Exception as error:
            self.log_message("NotchKiller: état non envoyé (%s)" % error)

    def _song(self):
        song = self.song
        return song() if callable(song) else song

    # MARK: Commandes

    def _receive(self):
        for _ in range(32):
            try:
                data, _ = self._sock.recvfrom(65536)
            except Exception:
                return
            try:
                message = json.loads(data.decode("utf-8"))
                self._run(message.get("cmd", ""), message)
            except Exception as error:
                self.log_message("NotchKiller: commande refusée (%s)" % error)

    def _run(self, cmd, msg):
        song = self._song()
        value = msg.get("value")
        if cmd == "play":
            song.start_playing()
        elif cmd == "stop":
            song.stop_playing()
        elif cmd == "toggle":
            song.stop_playing() if song.is_playing else song.start_playing()
        elif cmd == "continue":
            song.continue_playing()
        elif cmd == "record":
            song.record_mode = not song.record_mode
        elif cmd == "session_record":
            song.session_record = not song.session_record
        elif cmd == "overdub":
            song.arrangement_overdub = not song.arrangement_overdub
        elif cmd == "metronome":
            song.metronome = not song.metronome
        elif cmd == "loop":
            song.loop = not song.loop
        elif cmd == "punch_in":
            song.punch_in = not song.punch_in
        elif cmd == "punch_out":
            song.punch_out = not song.punch_out
        elif cmd == "tempo":
            song.tempo = max(20.0, min(999.0, float(value)))
        elif cmd == "tap_tempo":
            song.tap_tempo()
        elif cmd == "undo":
            if song.can_undo:
                song.undo()
        elif cmd == "redo":
            if song.can_redo:
                song.redo()
        elif cmd == "cue":
            cues = sorted(song.cue_points, key=lambda c: c.time)
            index = int(value)
            if 0 <= index < len(cues):
                cues[index].jump()
        elif cmd == "cue_next":
            song.jump_to_next_cue()
        elif cmd == "cue_prev":
            song.jump_to_prev_cue()
        elif cmd == "fire_scene":
            scenes = song.scenes
            index = int(value)
            if 0 <= index < len(scenes):
                scenes[index].fire()
        elif cmd == "fire_clip":
            tracks = self._visible_tracks()
            track, scene = int(msg.get("track", -1)), int(msg.get("scene", -1))
            if 0 <= track < len(tracks) and 0 <= scene < len(tracks[track].clip_slots):
                tracks[track].clip_slots[scene].fire()
        elif cmd == "stop_track":
            tracks = self._visible_tracks()
            index = int(value)
            if 0 <= index < len(tracks):
                tracks[index].stop_all_clips()
        elif cmd == "stop_all_clips":
            song.stop_all_clips()
        elif cmd == "grid":
            self._track_offset = max(0, int(msg.get("track", 0)))
            self._scene_offset = max(0, int(msg.get("scene", 0)))
        elif cmd in ("arm", "mute", "solo"):
            track = song.view.selected_track
            if cmd == "arm" and _get(track, "can_be_armed", False):
                track.arm = not track.arm
            elif cmd == "mute" and track != song.master_track:
                track.mute = not track.mute
            elif cmd == "solo" and track != song.master_track:
                track.solo = not track.solo

    # MARK: État

    def _visible_tracks(self):
        return [t for t in self._song().tracks if _get(t, "is_visible", True)]

    def _state(self):
        song = self._song()
        master = song.master_track
        selected = song.view.selected_track
        cues = sorted(song.cue_points, key=lambda c: c.time)
        return {
            "v": VERSION,
            "playing": song.is_playing,
            "tempo": song.tempo,
            "time": song.current_song_time,
            "length": _get(song, "last_event_time", 0.0),
            "num": song.signature_numerator,
            "den": song.signature_denominator,
            "record": song.record_mode,
            "session_record": _get(song, "session_record", False),
            "overdub": song.arrangement_overdub,
            "metronome": song.metronome,
            "loop": song.loop,
            "loop_start": song.loop_start,
            "loop_length": song.loop_length,
            "punch_in": song.punch_in,
            "punch_out": song.punch_out,
            "can_undo": song.can_undo,
            "can_redo": song.can_redo,
            "master": [_get(master, "output_meter_left", 0.0), _get(master, "output_meter_right", 0.0)],
            "groups": [self._meter(t) for t in song.tracks if _get(t, "is_foldable", False)][:12],
            "track": self._selected(selected, master),
            "cues": [{"name": c.name, "time": c.time} for c in cues][:24],
            "scenes": self._scenes(song),
            "grid": self._grid(),
            "offset": [self._track_offset, self._scene_offset],
            "size": [len(self._visible_tracks()), len(song.scenes)],
        }

    def _meter(self, track):
        return {
            "name": track.name,
            "color": _get(track, "color", 0),
            "l": _get(track, "output_meter_left", 0.0),
            "r": _get(track, "output_meter_right", 0.0),
            "mute": _get(track, "mute", False),
        }

    def _selected(self, track, master):
        slot = _get(self._song().view, "highlighted_clip_slot")
        clip = _get(slot, "clip") if slot is not None and _get(slot, "has_clip", False) else None
        return {
            "name": track.name,
            "color": _get(track, "color", 0),
            "master": track == master,
            "can_arm": bool(_get(track, "can_be_armed", False)),
            "arm": bool(_get(track, "arm", False)) if _get(track, "can_be_armed", False) else False,
            "mute": bool(_get(track, "mute", False)),
            "solo": bool(_get(track, "solo", False)),
            "clip": _get(clip, "name", None) if clip is not None else None,
            "l": _get(track, "output_meter_left", 0.0),
            "r": _get(track, "output_meter_right", 0.0),
        }

    def _scenes(self, song):
        scenes = list(song.scenes)[self._scene_offset:self._scene_offset + GRID_SCENES]
        return [{
            "name": s.name,
            "color": _get(s, "color", 0),
            "triggered": bool(_get(s, "is_triggered", False)),
        } for s in scenes]

    def _grid(self):
        tracks = self._visible_tracks()[self._track_offset:self._track_offset + GRID_TRACKS]
        columns = []
        for track in tracks:
            cells = []
            for slot in list(track.clip_slots)[self._scene_offset:self._scene_offset + GRID_SCENES]:
                clip = slot.clip if slot.has_clip else None
                if clip is None:
                    cells.append(None)
                    continue
                state = 0
                if _get(clip, "is_recording", False):
                    state = 3
                elif _get(clip, "is_playing", False):
                    state = 2
                elif _get(clip, "is_triggered", False) or _get(slot, "is_triggered", False):
                    state = 1
                cells.append({"name": clip.name, "color": _get(clip, "color", 0), "state": state})
            columns.append({
                "name": track.name,
                "color": _get(track, "color", 0),
                "clips": cells,
            })
        return columns
