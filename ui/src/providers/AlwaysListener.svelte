<script lang="ts">
	import { ReceiveNUI } from '@utils/ReceiveNUI'
	import { debugData } from '@utils/debugData'
	import { SendNUI } from '@utils/SendNUI'
	import { VISIBILITY, BROWSER_MODE, DISPATCH_MENU, DISPATCH_MENUS, DISPATCH, PLAYER, Locale, RESPOND_KEYBIND, MAX_CALL_LIST, MAX_VISIBLE_ALERTS, ALERT_POSITION, MAP_IMAGE, UNATTENDED_AFTER, PINNED_CODES, STATS, THUMBS_ENABLED, BLIPS_ENABLED, PRIORITY_ONLY, COMPACT_ALERTS, FOCUS_CALL } from '@store/stores';

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

	ReceiveNUI('stats', (data: any) => {
		STATS.set(data)
	});

	ReceiveNUI('clearAlerts', () => {
		DISPATCH.set([])
	});

	ReceiveNUI('focusCall', (id: any) => {
		FOCUS_CALL.set(id ?? null)
	});

	ReceiveNUI('setDispatchs', (data: any) => {
		DISPATCH_MENU.set(data)
	});

	ReceiveNUI('setupUI', (data: any) => {
		PLAYER.set(data.player)
		Locale.set(data.locales)
		RESPOND_KEYBIND.set(data.keybind)
		MAX_CALL_LIST.set(data.maxCallList)
		if (data.maxVisibleAlerts) MAX_VISIBLE_ALERTS.set(data.maxVisibleAlerts)
		if (data.alertPosition) ALERT_POSITION.set(data.alertPosition)
		if (data.unattendedAfter) UNATTENDED_AFTER.set(data.unattendedAfter)
		if (Array.isArray(data.pinnedCodes)) PINNED_CODES.set(data.pinnedCodes)
		// Per-player settings (dispatch settings modal) override the config
		// defaults set above. localStorage survives relogs; bad JSON is
		// ignored and the defaults stand.
		try {
			const saved = JSON.parse(localStorage.getItem('psd-settings') || '{}')
			if (typeof saved.alertPosition === 'string') ALERT_POSITION.set(saved.alertPosition)
			if (typeof saved.maxVisibleAlerts === 'number') MAX_VISIBLE_ALERTS.set(saved.maxVisibleAlerts)
			if (typeof saved.thumbsEnabled === 'boolean') THUMBS_ENABLED.set(saved.thumbsEnabled)
			if (typeof saved.blipsEnabled === 'boolean') BLIPS_ENABLED.set(saved.blipsEnabled)
			if (typeof saved.priorityOnly === 'boolean') PRIORITY_ONLY.set(saved.priorityOnly)
			if (typeof saved.compactAlerts === 'boolean') COMPACT_ALERTS.set(saved.compactAlerts)
			// The two Lua-gated prefs must reach the client on every session
			// start, not just when the modal is opened.
			SendNUI('setDispatchPrefs', {
				blips: typeof saved.blipsEnabled === 'boolean' ? saved.blipsEnabled : true,
				priorityOnly: saved.priorityOnly === true,
			})
		} catch (e) { /* defaults stand */ }
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
