<script>
  import { afterUpdate, onDestroy } from 'svelte';
  import Plate from './Plate.svelte';
  import { DISPATCH, removeDispatch, RESPOND_KEYBIND, MAX_VISIBLE_ALERTS, ALERT_POSITION, MAP_IMAGE, THUMBS_ENABLED, COMPACT_ALERTS, ALERT_DURATION, REDUCED_MOTION, UI_SCALE } from '@store/stores';
  import { fly } from 'svelte/transition';
  import { flip } from 'svelte/animate';
  import { DUR, EASE_OUT, edgeFor, signalIn, signalOut } from '@utils/motion';
  import { timeAgo } from '@utils/timeAgo';
  import MapThumb from './MapThumb.svelte';

  let notifications = [];

  DISPATCH.subscribe(value => {
    notifications = value || [];
  });

  function removeNotification(id) {
    removeDispatch(id);
  }

  // One expiry timer per call id; merged repeats (bumped ×count) reset it so
  // the refreshed card stays for its full duration again.
  const expiry = new Map(); // id -> { handle, rev }
  afterUpdate(() => {
    const seen = new Set();
    for (const { data, timer } of notifications) {
      seen.add(data.id);
      const rev = data.count || 1;
      const existing = expiry.get(data.id);
      if (existing && existing.rev === rev) continue;
      if (existing) clearTimeout(existing.handle);
      // Personal multiplier on Config.AlertTime (settings modal).
      const shown = Math.max(1000, timer * ($ALERT_DURATION || 1));
      expiry.set(data.id, {
        rev,
        handle: setTimeout(() => { expiry.delete(data.id); removeNotification(data.id); }, shown),
      });
    }
    for (const [id, e] of expiry) {
      if (!seen.has(id)) { clearTimeout(e.handle); expiry.delete(id); }
    }
  });
  onDestroy(() => { for (const [, e] of expiry) clearTimeout(e.handle); });

  // ── Placement (Config.AlertPosition) ───────────────────────────────────────
  $: [vPos, hPos] = ($ALERT_POSITION || 'top-right').split('-');
  $: wrapClasses = {
    top: 'items-start', center: 'items-center', bottom: 'items-end',
  }[vPos] + ' ' + {
    left: 'justify-start', center: 'justify-center', right: 'justify-end',
  }[hPos];
  // Entrance flies in from the nearest screen edge; the exit deliberately
  // does NOT mirror it — sliding back out reads as "undo", while a short
  // fade-and-shrink reads as "handled".
  // Which screen edge the stack is docked to — drives the wipe direction so
  // alerts always open inward from the nearest edge.
  $: alertEdge = edgeFor(vPos, hPos);

  $: ordered = notifications.slice().reverse(); // newest first
  $: capped = ordered.slice(0, $MAX_VISIBLE_ALERTS || 4);
  $: visible = vPos === 'bottom' ? capped.slice().reverse() : capped;
  $: hiddenCount = Math.max(0, ordered.length - capped.length);
  $: newestId = ordered.length ? ordered[0].data.id : null;

  // ── Field helpers ──────────────────────────────────────────────────────────
  function fmtDistance(m) {
    if (m == null) return null;
    return m < 1000 ? `${m} m` : `${(m / 1000).toFixed(1)} km`;
  }

  // The person line only shows what the caller actually revealed.
  // Same tables as the menu row: a shape reads faster than a word.
  const WEAPON_ICON = {
    pistol: 'fa-gun', smg: 'fa-gun', rifle: 'fa-crosshairs',
    shotgun: 'fa-gun', sniper: 'fa-crosshairs', heavy: 'fa-burst',
    taser: 'fa-bolt',
  };
  const WEAPON_LABEL = {
    pistol: 'Handgun', smg: 'Submachine gun', rifle: 'Rifle',
    shotgun: 'Shotgun', sniper: 'Long rifle', heavy: 'Heavy weapon',
    taser: 'Taser',
  };

  function personLine(d) {
    // Callsign is deliberately absent here: it renders as a badge pinned to
    // the name rather than as another dot-separated fact, because it belongs
    // to the officer beside it, not to the list.
    return [d.name, d.gender, d.number].filter(Boolean);
  }

  function vehicleBadges(d) {
    const out = [];
    if (d.color) out.push(d.color);
    if (d.class) out.push(d.class);
    if (d.doors) out.push(`${d.doors} doors`);
    return out;
  }
</script>

<div class="w-screen h-screen flex {wrapClasses} pointer-events-none p-[16px]" style="transform:scale({$UI_SCALE});transform-origin:{$ALERT_POSITION.includes('left') ? 'left' : 'right'} top;">
  <div class="flex flex-col gap-[7px] {hPos === 'right' ? 'items-end' : hPos === 'left' ? 'items-start' : 'items-center'}">
    {#if hiddenCount > 0 && vPos === 'top'}
      <p class="pd-more" transition:fly={{ y: -6, duration: DUR.fast, easing: EASE_OUT }}>+{hiddenCount} more active {hiddenCount === 1 ? 'alert' : 'alerts'}</p>
    {/if}

    {#each visible as dispatch (dispatch.data.id)}
      <div
        class="pd-panel pd-alert w-[340px] {(dispatch.data.priority ?? 3) <= 1 ? 'pd-panel--priority pd-alert--urgent' : ''} {(dispatch.data.priority ?? 3) <= 0 ? ($REDUCED_MOTION ? 'pd-panel--critical pd-no-pulse' : 'pd-panel--critical') : ''} {dispatch.data.responded ? ' pd-panel--responded' : ''} relative"
        in:signalIn={{ edge: alertEdge, priority: (dispatch.data.priority ?? 3) <= 1, duration: $REDUCED_MOTION ? 0 : DUR.alertIn }}
        out:signalOut={{ edge: alertEdge, duration: $REDUCED_MOTION ? 0 : DUR.alertOut }}
        animate:flip={{ duration: $REDUCED_MOTION ? 0 : DUR.base, easing: EASE_OUT }}
      >

        <!-- Header: what + when -->
        <div class="pd-head">
          <div class="pd-icon {(dispatch.data.priority ?? 3) <= 1 ? 'pd-icon--priority' : ''} {(dispatch.data.priority ?? 3) <= 0 ? 'pd-icon--critical' : ''}">
            <i class={dispatch.data.icon}></i>
          </div>
          <!-- Headline carries only the two fixed-width badges. The stacking
               ones (repeat count, escalation, hotspot) move to the badge row
               below, so what happened is never the part that gets cut. -->
          <span class="pd-badge {(dispatch.data.priority ?? 3) <= 1 ? 'pd-badge--red' : 'pd-badge--cyan'} flex-shrink-0">{dispatch.data.code}</span>
          {#if (dispatch.data.priority ?? 3) <= 0}<span class="pd-badge pd-badge--critical flex-shrink-0">Critical</span>{/if}
          <span class="pd-title truncate flex-1 min-w-0">{dispatch.data.message}</span>
          <span class="pd-time flex-shrink-0">{timeAgo(dispatch.data.time)}</span>
        </div>

        {#if (dispatch.data.count || 1) > 1 || dispatch.data.escalated || dispatch.data.hotspot}
          <div class="pd-tagrow">
            {#if (dispatch.data.count || 1) > 1}
              <span class="pd-badge pd-badge--red">×{dispatch.data.count} reports</span>
            {/if}
            {#if dispatch.data.escalated}
              <span class="pd-badge pd-badge--red" title="Auto-escalated after repeated reports"><i class="fas fa-arrow-up mr-[3px]"></i>Escalated</span>
            {/if}
            {#if dispatch.data.hotspot}
              <span class="pd-badge pd-badge--purple" title="Repeated incidents on this street"><i class="fas fa-fire mr-[3px]"></i>×{dispatch.data.hotspot} on this street</span>
            {/if}
          </div>
        {/if}

        <div class="px-[10px] py-[8px]">
          <!-- Map crop of the scene, centered on the call.

               Suppressed for answers. An alert carrying a footer is an ANSWER
               (plate check, record lookup) rather than a job — the same test
               client/plates.lua already uses — and it is targeted at the officer
               who asked for it, who is standing at the position. -->
          {#if $MAP_IMAGE && $THUMBS_ENABLED && !$COMPACT_ALERTS && !dispatch.data.footer}
            <MapThumb coords={dispatch.data.displayCoords || dispatch.data.coords} radius={dispatch.data.mapRadius || 0} priority={dispatch.data.priority} src={$MAP_IMAGE} />
          {/if}

          <!-- Location strip: the first thing a responder needs -->
          {#if !dispatch.data.footer && (dispatch.data.street || dispatch.data.distance != null || dispatch.data.heading)}
            <div class="pd-strip">
              <div class="pd-strip-row">
                <i class="fas fa-location-dot text-[10px] opacity-50"></i>
                <span class="pd-strip-title">{dispatch.data.street || 'Unknown location'}</span>
                {#if dispatch.data.distance != null}
                  <span class="pd-dist"><i class="fas fa-route"></i>{fmtDistance(dispatch.data.distance)}</span>
                {/if}
                {#if dispatch.data.heading}
                  <span class="pd-badge pd-badge--blue"><i class="fas fa-compass mr-[3px]"></i>{dispatch.data.heading}</span>
                {/if}
              </div>
            </div>
          {/if}

          <!-- Vehicle strip: ImpoundForm's vehicle-strip, verbatim language -->
          {#if !$COMPACT_ALERTS && ( dispatch.data.vehicle || dispatch.data.plate)}
            <div class="pd-strip">
              <div class="pd-strip-row">
                <i class="fas fa-car text-[10px] opacity-50"></i>
                <span class="pd-strip-title pd-strip-title--tight">{dispatch.data.vehicle || 'Unknown vehicle'}</span>
                {#if dispatch.data.plate}
                  <Plate plate={dispatch.data.plate} index={dispatch.data.plateIndex} />
                {/if}
              </div>
              {#if vehicleBadges(dispatch.data).length}
                <div class="pd-strip-badges">
                  {#each vehicleBadges(dispatch.data) as b}
                    <span class="pd-badge">{b}</span>
                  {/each}
                </div>
              {/if}
            </div>
          {/if}

          <!-- Danger banner: weapons are a flag, not a table row -->
          {#if !$COMPACT_ALERTS && (dispatch.data.weapon || dispatch.data.automaticGunFire)}
            <!-- Same strip anatomy and threat tiers as the menu row. -->
            <div class="pd-strip pd-weap pd-weap--t{dispatch.data.weaponTier || 1}">
              <div class="pd-strip-row">
                <i class="fas {WEAPON_ICON[dispatch.data.weaponClass] || 'fa-gun'} text-[10px]"></i>
                <span class="pd-strip-title pd-strip-title--tight">
                  {WEAPON_LABEL[dispatch.data.weaponClass] || dispatch.data.weapon || 'Shots fired'}
                </span>
                {#if dispatch.data.weapon && WEAPON_LABEL[dispatch.data.weaponClass]}
                  <span class="pd-weap-model">{dispatch.data.weapon}</span>
                {/if}
                {#if dispatch.data.automaticGunFire}
                  <span class="pd-badge pd-badge--red">Automatic</span>
                {/if}
              </div>
            </div>
          {/if}

          <!-- Caller / suspect facts -->
          {#if !$COMPACT_ALERTS && (personLine(dispatch.data).length || dispatch.data.callsign)}
            <div class="pd-person">
              <i class="fas fa-user"></i>
              {#if dispatch.data.callsign}
                <span class="pd-badge pd-mono">{dispatch.data.callsign}</span>
              {/if}
              {#each personLine(dispatch.data) as part, i}
                {#if i > 0}<span class="opacity-40">·</span>{/if}
                <span>{part}</span>
              {/each}
            </div>
          {/if}

          <!-- Free-text information as a quoted note -->
          {#if dispatch.data.information}
            <div class="pd-note">{dispatch.data.information}</div>
          {/if}

          {#if dispatch.data.dispatchNote}
            <div class="pd-note pd-note--dispatch">
              <span class="pd-note-tag">Dispatch</span>{dispatch.data.dispatchNote}
            </div>
          {/if}

          <!-- Live responder count: fed by the server's unitCount broadcasts -->
          {#if (dispatch.data.unitCount || 0) > 0}
            <div class="pd-person"><i class="fas fa-user-group"></i><span class="text-[#4ade80]">{dispatch.data.unitCount} responding</span></div>
          {/if}

          {#if dispatch.data.footer}
            <!-- Alerts that are an ANSWER rather than a job (plate checks,
                 record lookups) supply their own footer: no respond prompt,
                 because there is nothing to respond to. -->
            <div class="pd-assigned {dispatch.data.footer.tone === 'alert' ? 'pd-assigned--alert' : ''}">
              <i class={dispatch.data.footer.icon || 'fas fa-database'}></i>
              <span>{dispatch.data.footer.text}</span>
              {#if dispatch.data.footer.sub}
                <span class="pd-assigned-sub">{dispatch.data.footer.sub}</span>
              {/if}
            </div>
          {:else if dispatch.data.assigned}
            <!-- Dispatcher assignment: the waypoint is already set and the
                 unit is already attached, so a respond prompt would be a lie.
                 Confirmation instead. -->
            <div class="pd-assigned">
              <i class="fas fa-headset"></i>
              <span>Assigned by dispatch</span>
              <span class="pd-assigned-sub"><i class="fas fa-location-arrow"></i> waypoint set</span>
            </div>
          {:else if dispatch.data.id === newestId && !dispatch.data.responded}
            <div class="pd-respond"><span class="pd-kbd">{$RESPOND_KEYBIND}</span> Respond — attach &amp; set waypoint</div>
          {/if}
        </div>

        {#key dispatch.data.count}
          <div class="pd-toast-timer" style="--dur:{Math.max(1000, dispatch.timer * ($ALERT_DURATION || 1))}ms"></div>
        {/key}
      </div>
    {/each}

    {#if hiddenCount > 0 && vPos !== 'top'}
      <p class="pd-more" transition:fly={{ y: 6, duration: DUR.fast, easing: EASE_OUT }}>+{hiddenCount} more active {hiddenCount === 1 ? 'alert' : 'alerts'}</p>
    {/if}
  </div>
</div>