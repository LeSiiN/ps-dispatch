<script lang="ts">
	import { ReceiveNUI } from '@utils/ReceiveNUI'
	import { debugData } from '@utils/debugData'
	import { SendNUI } from '@utils/SendNUI'
	import { VISIBILITY, BROWSER_MODE, DISPATCH_MENU, DISPATCH_MENUS, DISPATCH, PLAYER, Locale, RESPOND_KEYBIND, MAX_CALL_LIST, MAX_VISIBLE_ALERTS, ALERT_POSITION, MAP_IMAGE, UNATTENDED_AFTER, PINNED_CODES, STATS, THUMBS_ENABLED, BLIPS_ENABLED, PRIORITY_ONLY, COMPACT_ALERTS, FOCUS_CALL, ALERT_TYPES, MUTED_CODES, ALERT_DURATION, REDUCED_MOTION, PLATE_HITS, MENU_TAB, PLATES_ENABLED, INCIDENTS, MAY_DECLARE, UI_SCALE } from '@store/stores';

	debugData([
		{
			action: 'setVisible',
			data: true,
		},
	])

	debugData([
		{
			action: 'setBrowserMode',
			data: true
		},
	])

	function browserHideAndShow(e: KeyboardEvent) {
		if (e.key === '=') {
			$VISIBILITY = true
		}
	}

	ReceiveNUI('setBrowserMode', (data: boolean) => {
		BROWSER_MODE.set(data)
		console.log('browser mode enabled')
		if (data) {
			window.addEventListener('keydown', browserHideAndShow)
		} else {
			window.removeEventListener('keydown', browserHideAndShow)
		}
	})

	ReceiveNUI('newCall', (data: any) => {
		DISPATCH.update(dispatches => {
			dispatches = dispatches || [];
			// Merged repeat of an existing call (server bumped its ×count):
			// update the popup in place instead of stacking a duplicate.
			const idx = dispatches.findIndex(d => d.data.id === data.data.id);
			if (idx !== -1) {
				dispatches[idx] = data;
				return dispatches;
			}
			dispatches.push(data);
			return dispatches;
		});

		// Keep the menu in step. Its list is a snapshot taken when it opened,
		// so a call arriving while it is on screen would otherwise be invisible
		// there until you closed and reopened it — with the popup for that same
		// call sitting right next to an empty board.
		if (!data?.data?.listed) return;
		DISPATCH_MENU.update(list => {
			if (!Array.isArray(list)) return list;
			const idx = list.findIndex(c => c?.id === data.data.id);
			if (idx !== -1) {
				// Merged repeat: the server bumped its count, so replace in
				// place rather than adding the same call twice.
				list[idx] = data.data;
				return [...list];
			}
			return [...list, data.data];
		});
	});

	ReceiveNUI('unitCount', (payload: any) => {
		DISPATCH.update(dispatches => {
			if (!dispatches) return dispatches;
			const d = dispatches.find(x => x.data.id === payload.id);
			if (d) d.data.unitCount = payload.count;
			return [...dispatches];
		});
		// Also patch the menu list so the pending/active board re-partitions
		// live when SOMEONE ELSE attaches (unit details follow on refresh).
		DISPATCH_MENU.update(list => {
			if (!list) return list;
			const d = list.find(x => x.id === payload.id);
			if (d) d.unitsLive = payload.count;
			return [...list];
		});
	});

	ReceiveNUI('callResponded', (id: any) => {
		DISPATCH.update(dispatches => {
			if (!dispatches) return dispatches;
			const d = dispatches.find(x => x.data.id === id);
			if (d) d.data.responded = true;
			return [...dispatches];
		});
	});

	ReceiveNUI('callUnresponded', (id: any) => {
		DISPATCH.update(dispatches => {
			if (!dispatches) return dispatches;
			const d = dispatches.find(x => x.data.id === id);
			if (d) d.data.responded = false;
			return [...dispatches];
		});
	});

	ReceiveNUI('platesEnabled', (data: any) => {
		PLATES_ENABLED.set(data === true)
		if (data !== true) MENU_TAB.set('calls')
	});

	ReceiveNUI('resetSettings', () => {
		UI_SCALE.set(1)
	});

	ReceiveNUI('incidents', (data: any) => {
		INCIDENTS.set(Array.isArray(data) ? data : []);
	});

	ReceiveNUI('mayDeclareIncident', (data: any) => {
		MAY_DECLARE.set(data === true);
	});

	ReceiveNUI('plateHits', (data: any) => {
		PLATE_HITS.set(Array.isArray(data) ? data : []);
	});

	ReceiveNUI('stats', (data: any) => {
		STATS.set(data)
	});

	ReceiveNUI('callCleared', (id: any) => {
		DISPATCH.update(list => (list || []).filter(d => d.data.id !== id));
		DISPATCH_MENU.update(list => (list || []).filter(d => d.id !== id));
	});

	ReceiveNUI('callNote', (payload: any) => {
		DISPATCH.update(list => {
			const d = (list || []).find(x => x.data.id === payload.id);
			if (d) d.data.dispatchNote = payload.note;
			return [...(list || [])];
		});
		DISPATCH_MENU.update(list => {
			const d = (list || []).find(x => x.id === payload.id);
			if (d) d.dispatchNote = payload.note;
			return [...(list || [])];
		});
	});

	ReceiveNUI('clearAlerts', () => {
		DISPATCH.set([])
	});

	ReceiveNUI('focusCall', (id: any) => {
		FOCUS_CALL.set(id ?? null)
	});

	ReceiveNUI('setDispatchs', (data: any) => {
		DISPATCH_MENU.set(data)
		// Opening onto an empty call list while the scanner log has entries would
		// hide the only thing there is to look at.
		if (!data?.length) {
			let hits: any[] = [];
			PLATE_HITS.subscribe(v => hits = v)();
			if (hits.length) MENU_TAB.set('plates');
		}
	});

	ReceiveNUI('setupUI', (data: any) => {
		PLAYER.set(data.player)
		Locale.set(data.locales)
		RESPOND_KEYBIND.set(data.keybind)
		MAX_CALL_LIST.set(data.maxCallList)
		if (data.maxVisibleAlerts) MAX_VISIBLE_ALERTS.set(data.maxVisibleAlerts)
		if (data.alertPosition) ALERT_POSITION.set(data.alertPosition)
		if (data.unattendedAfter) UNATTENDED_AFTER.set(data.unattendedAfter)
		PLATES_ENABLED.set(data.platesEnabled !== false)
		// A stale 'plates' tab from a previous session would leave the menu on a
		// panel that no longer exists.
		if (data.platesEnabled === false) MENU_TAB.set('calls')
		if (Array.isArray(data.pinnedCodes)) PINNED_CODES.set(data.pinnedCodes)
		if (Array.isArray(data.alertTypes)) ALERT_TYPES.set(data.alertTypes)
		// Per-player settings (dispatch settings modal) override the config
		// defaults set above. They arrive from Lua's KVP store, which unlike
		// localStorage survives a CEF cache clear. Bad JSON is ignored and the
		// defaults stand.
		try {
			const saved = JSON.parse(data.savedSettings || localStorage.getItem('psd-settings') || '{}')
			// Clamped on load, not just on save: anyone who stored a larger value
			// before the ceiling existed would otherwise stay locked out of the
			// very dialog that could fix it.
			if (typeof saved.uiScale === 'number') UI_SCALE.set(Math.min(1.3, Math.max(0.8, saved.uiScale)))
			if (typeof saved.alertPosition === 'string') ALERT_POSITION.set(saved.alertPosition)
			if (typeof saved.maxVisibleAlerts === 'number') MAX_VISIBLE_ALERTS.set(saved.maxVisibleAlerts)
			if (typeof saved.thumbsEnabled === 'boolean') THUMBS_ENABLED.set(saved.thumbsEnabled)
			if (typeof saved.blipsEnabled === 'boolean') BLIPS_ENABLED.set(saved.blipsEnabled)
			if (typeof saved.priorityOnly === 'boolean') PRIORITY_ONLY.set(saved.priorityOnly)
			if (typeof saved.compactAlerts === 'boolean') COMPACT_ALERTS.set(saved.compactAlerts)
			if (Array.isArray(saved.mutedCodes)) MUTED_CODES.set(saved.mutedCodes)
			if (typeof saved.alertDuration === 'number') ALERT_DURATION.set(saved.alertDuration)
			if (typeof saved.reducedMotion === 'boolean') REDUCED_MOTION.set(saved.reducedMotion)
			// The two Lua-gated prefs must reach the client on every session
			// start, not just when the modal is opened.
			SendNUI('setDispatchPrefs', {
				blips: typeof saved.blipsEnabled === 'boolean' ? saved.blipsEnabled : true,
				priorityOnly: saved.priorityOnly === true,
				mutedCodes: Array.isArray(saved.mutedCodes) ? saved.mutedCodes : [],
			})
		} catch (e) { /* defaults stand */ }
		// CSS keyframes (priority flash, timer bar) are not Svelte
		// transitions, so they need a document-level switch of their own.
		REDUCED_MOTION.subscribe(v =>
			document.documentElement.classList.toggle('psd-reduced-motion', v))
		// Thumbnails only activate once the MDT's map image demonstrably
		// loads — wrong resource name / missing MDT just means no thumbs,
		// never a broken grey box on every alert.
		if (typeof data.mapImage === 'string' && data.mapImage) {
			const probe = new Image()
			probe.onload = () => MAP_IMAGE.set(data.mapImage)
			probe.onerror = () => MAP_IMAGE.set(null)
			probe.src = data.mapImage
		}
	});

</script>