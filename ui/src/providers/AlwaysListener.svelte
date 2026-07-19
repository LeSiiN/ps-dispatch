<script lang="ts">
	import { ReceiveNUI } from '@utils/ReceiveNUI'
	import { debugData } from '@utils/debugData'
	import { VISIBILITY, BROWSER_MODE, DISPATCH_MENU, DISPATCH_MENUS, DISPATCH, PLAYER, Locale, RESPOND_KEYBIND, MAX_CALL_LIST, MAX_VISIBLE_ALERTS, ALERT_POSITION, MAP_IMAGE, UNATTENDED_AFTER, shortCalls } from '@store/stores';

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
		// Thumbnails only activate once the MDT's map image demonstrably
		// loads — wrong resource name / missing MDT just means no thumbs,
		// never a broken grey box on every alert.
		if (typeof data.mapImage === 'string' && data.mapImage) {
			const probe = new Image()
			probe.onload = () => MAP_IMAGE.set(data.mapImage)
			probe.onerror = () => MAP_IMAGE.set(null)
			probe.src = data.mapImage
		}
		shortCalls.set(data.shortCalls)
	});

</script>
