<script>
  import { afterUpdate, onDestroy } from 'svelte';
  import { DISPATCH, removeDispatch, RESPOND_KEYBIND, MAX_VISIBLE_ALERTS, ALERT_POSITION, MAP_IMAGE, THUMBS_ENABLED, COMPACT_ALERTS, ALERT_DURATION, REDUCED_MOTION } from '@store/stores';
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
  function personLine(d) {
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

<div class="w-screen h-screen flex {wrapClasses} pointer-events-none p-[16px]">
  <div class="flex flex-col gap-[7px] {hPos === 'right' ? 'items-end' : hPos === 'left' ? 'items-start' : 'items-center'}">
    {#if hiddenCount > 0 && vPos === 'top'}
      <p class="pd-more" transition:fly={{ y: -6, duration: DUR.fast, easing: EASE_OUT }}>+{hiddenCount} more active {hiddenCount === 1 ? 'alert' : 'alerts'}</p>
    {/if}

    {#each visible as dispatch (dispatch.data.id)}
      <div
        class="pd-panel pd-alert w-[340px] {dispatch.data.priority == 1 ? 'pd-panel--priority pd-alert--urgent' : ''} relative"
        in:signalIn={{ edge: alertEdge, priority: dispatch.data.priority == 1, duration: $REDUCED_MOTION ? 0 : DUR.alertIn }}
        out:signalOut={{ edge: alertEdge, duration: $REDUCED_MOTION ? 0 : DUR.alertOut }}
        animate:flip={{ duration: $REDUCED_MOTION ? 0 : DUR.base, easing: EASE_OUT }}
      >

        <!-- Header: what + when -->
        <div class="pd-head">
          <div class="pd-icon {dispatch.data.priority == 1 ? 'pd-icon--priority' : ''}">
            <i class={dispatch.data.icon}></i>
          </div>
          <span class="pd-badge {dispatch.data.priority == 1 ? 'pd-badge--red' : 'pd-badge--cyan'}">{dispatch.data.code}</span>
          {#if (dispatch.data.count || 1) > 1}
            <span class="pd-badge pd-badge--red">×{dispatch.data.count}</span>
          {/if}
          {#if dispatch.data.escalated}
            <span class="pd-badge pd-badge--red" title="Auto-escalated after repeated reports"><i class="fas fa-arrow-up mr-[3px]"></i>ESC</span>
          {/if}
          {#if dispatch.data.hotspot}
            <span class="pd-badge pd-badge--purple" title="Repeated incidents on this street"><i class="fas fa-fire mr-[3px]"></i>×{dispatch.data.hotspot}</span>
          {/if}
          <span class="pd-title truncate">{dispatch.data.message}</span>
          <span class="pd-time">{timeAgo(dispatch.data.time)}</span>
        </div>

        <div class="px-[10px] py-[8px]">
          <!-- Map crop of the scene, centered on the call -->
          {#if $MAP_IMAGE && $THUMBS_ENABLED && !$COMPACT_ALERTS}
            <MapThumb coords={dispatch.data.displayCoords || dispatch.data.coords} radius={dispatch.data.mapRadius || 0} priority={dispatch.data.priority} src={$MAP_IMAGE} />
          {/if}

          <!-- Location strip: the first thing a responder needs -->
          {#if dispatch.data.street || dispatch.data.distance != null || dispatch.data.heading}
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
                <span class="pd-strip-title">{dispatch.data.vehicle || 'Unknown vehicle'}</span>
                {#if dispatch.data.plate}
                  <span class="pd-plate">{dispatch.data.plate}</span>
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
          {#if !$COMPACT_ALERTS && ( dispatch.data.weapon || dispatch.data.automaticGunFire)}
            <div class="pd-danger {dispatch.data.automaticGunFire ? 'pd-danger--red' : ''}">
              <i class="fas fa-gun"></i>
              <span>
                {#if dispatch.data.weapon}{dispatch.data.weapon}{:else}Shots fired{/if}
                {#if dispatch.data.automaticGunFire}&nbsp;· Automatic fire{/if}
              </span>
            </div>
          {/if}

          <!-- Caller / suspect facts -->
          {#if !$COMPACT_ALERTS && ( personLine(dispatch.data).length)}
            <div class="pd-person">
              <i class="fas fa-user"></i>
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
          {#if (dispatch.data.unitCount || 0) > 0 && !dispatch.data.responded}
            <div class="pd-person"><i class="fas fa-user-group"></i><span class="text-[#4ade80]">{dispatch.data.unitCount} responding</span></div>
          {/if}

          {#if dispatch.data.assigned}
            <!-- Dispatcher assignment: the waypoint is already set and the
                 unit is already attached, so a respond prompt would be a lie.
                 Confirmation instead. -->
            <div class="pd-assigned">
              <i class="fas fa-headset"></i>
              <span>Assigned by dispatch</span>
              <span class="pd-assigned-sub"><i class="fas fa-location-arrow"></i> waypoint set</span>
            </div>
          {:else if dispatch.data.responded}
            <div class="pd-responding"><i class="fas fa-circle-check"></i> Responding{#if (dispatch.data.unitCount || 0) > 1}&nbsp;· {dispatch.data.unitCount} units{/if}</div>
          {:else if dispatch.data.id === newestId}
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
