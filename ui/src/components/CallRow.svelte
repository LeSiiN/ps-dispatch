<script>
  // One call in a dispatch panel: compact row, expandable in place to the
  // full section anatomy (map thumb, location/vehicle strips, danger banner,
  // person line, note, units, attach button). Extracted from Menu.svelte so
  // the pending list and the Active Calls board share one implementation.
  import { createEventDispatcher } from 'svelte';
  import Plate from './Plate.svelte';
  import { slide } from 'svelte/transition';
  import { DUR, EASE_OUT } from '@utils/motion';
  import { PLAYER, Locale, MAP_IMAGE, UNATTENDED_AFTER, PINNED_CODES, THUMBS_ENABLED, REDUCED_MOTION } from '@store/stores';
  import { timeAgo } from '@utils/timeAgo';
  import { SendNUI } from '@utils/SendNUI';
  import MapThumb from './MapThumb.svelte';

  export let dispatch;              // the call
  export let expanded = false;      // parent-controlled (one open at a time)
  export let showUnitsInline = false; // Active board: callsigns in the row
  export let isIncident = false;    // declared a major incident
  export let mayDeclare = false;    // this player's grade allows declaring

  // Declaring changes everyone's board, so it takes the same two-step confirm
  // the clear button already uses in this file.
  // Same copy path as the plate log: navigator.clipboard needs a secure
  // context, which the NUI is not.
  let copiedPlate = false;
  function copyPlate() {
    try {
      const ta = document.createElement('textarea');
      ta.value = dispatch.plate;
      ta.style.cssText = 'position:fixed;opacity:0;pointer-events:none;';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      ta.remove();
      copiedPlate = true;
      setTimeout(() => (copiedPlate = false), 1400);
    } catch { /* nothing sensible to say if the host blocks it */ }
  }

  // Silhouette per class — a shape reads faster than a word when you are
  // driving. Font Awesome has no shotgun or SMG, so the closest gun glyph
  // stands in and the label carries the detail.
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

  let confirmDeclare = false;
  $: if (!expanded) confirmDeclare = false;

  function toggleIncident() {
    if (isIncident) {
      SendNUI('standDownIncident', { id: dispatch.id });
      return;
    }
    if (!confirmDeclare) { confirmDeclare = true; return; }
    confirmDeclare = false;
    SendNUI('declareIncident', {
      id: dispatch.id,
      title: dispatch.message,
      code: dispatch.code,
      street: dispatch.street,
    });
  }

  const emit = createEventDispatcher();
  let showAllUnits = false;
  // Units arrive in attach order from the server, so the first slice is always
  // the units that got there first — no sorting needed.
  const UNIT_LIMIT = 5;

  // Priority 0 sits above the existing red. Everything that used to ask
  // "== 1" now asks "<= 1", so critical inherits every urgent treatment and
  // adds its own on top — otherwise the most important call on the board
  // would have rendered as routine.
  $: isCritical = (dispatch.priority ?? 3) <= 0;
  $: isUrgent = (dispatch.priority ?? 3) <= 1;
  let confirmClear = false;
  let noteDraft = '';
  let noteOpen = false;

  // Reset the transient editor state only when this row actually switches to
  // a DIFFERENT call. Reacting to `dispatch` itself would fire on every store
  // update (unit counts and notes hand down fresh array copies), closing the
  // note editor mid-typing.
  let lastId = null;
  $: if (dispatch.id !== lastId) {
    lastId = dispatch.id;
    confirmClear = false;
    noteOpen = false;
  }

  function openNote() {
    noteDraft = dispatch.dispatchNote || '';
    noteOpen = true;
  }

  function saveNote() {
    SendNUI('setCallNote', { id: dispatch.id, note: noteDraft });
    noteOpen = false;
  }

  function clearCall() {
    if (!confirmClear) { confirmClear = true; return; }
    SendNUI('clearCall', { id: dispatch.id });
    confirmClear = false;
  }

  // Live count support: a unitCount push is always newer than the units
  // array from the last list refresh, so it wins when present — in both
  // directions (remote detaches must drop the badge too).
  $: unitCount = dispatch.unitsLive !== undefined ? dispatch.unitsLive : (dispatch.units?.length || 0);

  function CheckIfAttached(units, player) {
    for (let i = 0; i < (units?.length || 0); i++) {
      if (units[i].citizenid === player) return true;
    }
    return false;
  }

  // Triage: true when nobody is attached and the call has been waiting
  // longer than Config.UnattendedAfter minutes.
  function unattendedFor(d) {
    if (!$UNATTENDED_AFTER) return 0;
    if (unitCount > 0) return 0;
    const min = Math.floor((Date.now() - d.time) / 60000);
    return min >= $UNATTENDED_AFTER ? min : 0;
  }

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

<div data-call-id={dispatch.id}>
  <button class="pd-row {isUrgent ? 'pd-row--priority' : ''} {isCritical ? ($REDUCED_MOTION ? 'pd-row--critical pd-no-pulse' : 'pd-row--critical') : ''} {isIncident ? 'pd-row--incident' : ''}" class:pd-row--open={expanded} on:click={() => emit('toggle')}>
    <div class="pd-icon {isUrgent ? 'pd-icon--priority' : ''} {isCritical ? 'pd-icon--critical' : ''}">
      <i class={dispatch.icon}></i>
    </div>
    <div class="flex flex-col min-w-0 flex-1 gap-[2px]">
      <!-- Only the two fixed-width badges share the headline. Everything that
           can stack up — pin, repeat count, hotspot — sits on the meta line
           below, because the one thing that must never be squeezed out is
           what actually happened. -->
      <div class="flex items-center gap-[6px] min-w-0">
        <span class="pd-badge {isUrgent ? 'pd-badge--red' : 'pd-badge--cyan'} flex-shrink-0">{dispatch.code}</span>
        {#if isCritical}<span class="pd-badge pd-badge--critical flex-shrink-0">Critical</span>{/if}
        <span class="pd-row-msg flex-1 min-w-0">{dispatch.message}</span>
      </div>
      <div class="flex items-center gap-[8px] min-w-0">
        <span class="pd-kv-label flex-shrink-0">#{dispatch.id}</span>
        {#if dispatch.street}<span class="text-[10px] opacity-40 truncate">{dispatch.street}</span>{/if}
        <span class="pd-time flex-shrink-0">{timeAgo(dispatch.time)}</span>
        {#if $PINNED_CODES.includes(dispatch.codeName)}
          <span class="pd-badge pd-badge--red flex-shrink-0" title="Pinned critical call"><i class="fas fa-thumbtack"></i></span>
        {/if}
        {#if (dispatch.count || 1) > 1}
          <span class="pd-badge pd-badge--red flex-shrink-0">×{dispatch.count}</span>
        {/if}
        {#if dispatch.hotspot}
          <span class="pd-badge pd-badge--purple flex-shrink-0" title="Repeated incidents on this street"><i class="fas fa-fire mr-[3px]"></i>×{dispatch.hotspot}</span>
        {/if}
      </div>
      {#if showUnitsInline && dispatch.units?.length}
        <div class="flex items-center gap-[4px] flex-wrap">
          {#each dispatch.units.slice(0, UNIT_LIMIT) as unit}
            <span class="pd-badge {unit.job.type == "leo" ? "pd-badge--blue" : unit.job.type == "ems" ? "pd-badge--red" : ""} pd-mono">{unit.metadata.callsign || unit.charinfo.lastname}</span>
          {/each}
          {#if dispatch.units.length > UNIT_LIMIT}
            <span class="pd-badge">+{dispatch.units.length - UNIT_LIMIT}</span>
          {/if}
        </div>
      {/if}
    </div>
    <div class="flex items-center gap-[6px] flex-shrink-0">
      {#if unattendedFor(dispatch)}
        <span class="pd-badge pd-badge--amber" title="No units attached"><i class="fas fa-clock mr-[3px]"></i>{unattendedFor(dispatch)}m</span>
      {/if}
      {#if unitCount > 0}
        <span class="pd-badge pd-badge--green"><i class="fas fa-user-group mr-[3px]"></i>{unitCount}</span>
      {/if}
      <i class="fas fa-chevron-{expanded ? 'up' : 'down'} text-[9px] opacity-35"></i>
    </div>
  </button>

  {#if expanded}
    <div class="pd-detail" transition:slide={{ duration: DUR.base, easing: EASE_OUT }}>
      <!-- Answers get neither a map nor a location. An alert carrying a footer
           is an ANSWER — a plate check, a record lookup — which is the same test
           client/plates.lua uses to decide what belongs in the plate log. It is
           targeted at the officer who asked, and that officer is standing at the
           position, so a map centred on where they already are sits above the
           thing they actually wanted to read. A job is somewhere you have to go
           and keeps both. -->
      {#if $MAP_IMAGE && $THUMBS_ENABLED && !dispatch.footer}
        <!-- Click opens the enlarged, zoomable map (handled by the parent so
             there is only ever one overlay). -->
        <div class="pd-thumb-click" title="Enlarge map" on:click={() => emit('expandMap')}>
          <MapThumb coords={dispatch.displayCoords || dispatch.coords} radius={dispatch.mapRadius || 0} priority={dispatch.priority} src={$MAP_IMAGE} height={92} />
          <span class="pd-thumb-zoom"><i class="fas fa-magnifying-glass-plus"></i></span>
        </div>
      {/if}
      {#if !dispatch.footer && (dispatch.street || dispatch.heading)}
        <div class="pd-strip">
          <div class="pd-strip-row">
            <i class="fas fa-location-dot text-[10px] opacity-50"></i>
            <span class="pd-strip-title">{dispatch.street || 'Unknown location'}</span>
            {#if dispatch.heading}
              <span class="pd-badge pd-badge--blue"><i class="fas fa-compass mr-[3px]"></i>{dispatch.heading}</span>
            {/if}
          </div>
        </div>
      {/if}

      {#if dispatch.vehicle || dispatch.plate}
        <div class="pd-strip">
          <div class="pd-strip-row">
            <i class="fas fa-car text-[10px] opacity-50"></i>
            <span class="pd-strip-title pd-strip-title--tight">{dispatch.vehicle || 'Unknown vehicle'}</span>
            {#if dispatch.plate}
              <Plate plate={dispatch.plate} index={dispatch.plateIndex} />
              <!-- Only reachable once the call is expanded, so it never
                   clutters the collapsed board. -->
              <span
                class="pd-copy"
                class:pd-copy--done={copiedPlate}
                role="button"
                tabindex="-1"
                title={copiedPlate ? 'Copied' : 'Copy plate'}
                on:click|stopPropagation={copyPlate}
                on:keydown|stopPropagation
              >
                <i class="fas {copiedPlate ? 'fa-check' : 'fa-copy'}"></i>
              </span>
            {/if}
          </div>
          {#if vehicleBadges(dispatch).length}
            <div class="pd-strip-badges">
              {#each vehicleBadges(dispatch) as b}
                <span class="pd-badge">{b}</span>
              {/each}
            </div>
          {/if}
        </div>
      {/if}

      {#if dispatch.weapon || dispatch.automaticGunFire}
        <!-- Same strip anatomy as location, vehicle and person. The urgency
             now rides on the colour rather than on a full-width slab that
             shouted just as loudly for a handgun as for an RPG. -->
        <div class="pd-strip pd-weap pd-weap--t{dispatch.weaponTier || 1}">
          <div class="pd-strip-row">
            <i class="fas {WEAPON_ICON[dispatch.weaponClass] || 'fa-gun'} text-[10px]"></i>
            <span class="pd-strip-title pd-strip-title--tight">
              {WEAPON_LABEL[dispatch.weaponClass] || dispatch.weapon || 'Shots fired'}
            </span>
            {#if dispatch.weapon && WEAPON_LABEL[dispatch.weaponClass]}
              <span class="pd-weap-model">{dispatch.weapon}</span>
            {/if}
            {#if dispatch.automaticGunFire}
              <span class="pd-badge pd-badge--red">Automatic</span>
            {/if}
            {#if (dispatch.count || 1) > 1}
              <span class="pd-badge">×{dispatch.count} reports</span>
            {/if}
          </div>
        </div>
      {/if}

      {#if personLine(dispatch).length || dispatch.callsign}
        <div class="pd-person">
          <i class="fas fa-user"></i>
          {#if dispatch.callsign}
            <span class="pd-badge pd-mono">{dispatch.callsign}</span>
          {/if}
          {#each personLine(dispatch) as part, i}
            {#if i > 0}<span class="opacity-40">·</span>{/if}
            <span>{part}</span>
          {/each}
        </div>
      {/if}

      {#if dispatch.information}
        <div class="pd-note">{dispatch.information}</div>
      {/if}

      {#if dispatch.dispatchNote && !noteOpen}
        <div class="pd-note pd-note--dispatch">
          <span class="pd-note-tag">Dispatch</span>{dispatch.dispatchNote}
        </div>
      {/if}

      {#if noteOpen}
        <div class="pd-note-editor">
          <input
            class="pd-input"
            placeholder="Note for every unit on this call…"
            maxlength="240"
            bind:value={noteDraft}
            on:keydown={(e) => { if (e.key === 'Enter') saveNote(); if (e.key === 'Escape') noteOpen = false; }}
          />
          <button class="pd-btn pd-btn--green" on:click={saveNote}><i class="fas fa-check"></i></button>
          <button class="pd-btn" on:click={() => noteOpen = false}><i class="fas fa-xmark"></i></button>
        </div>
      {/if}

      {#if dispatch.units.length > 0}
        <div class="mt-[7px]">
          <span class="pd-kv-label">Attached Units</span>
          <div class="mt-[3px]">
            {#each dispatch.units.slice(0, showAllUnits ? dispatch.units.length : UNIT_LIMIT) as unit}
              <div class="pd-unit">
                {#if unit.metadata.callsign}<span class="pd-badge pd-mono">{unit.metadata.callsign}</span>{/if}
                <span class="pd-badge {unit.job.type == "leo" ? "pd-badge--blue" : unit.job.type == "ems" ? "pd-badge--red" : ""} uppercase">{unit.job.name}</span>
                <span class="truncate">{unit.charinfo.firstname} {unit.charinfo.lastname}</span>
              </div>
            {/each}
            {#if dispatch.units.length > UNIT_LIMIT}
              <!-- Deliberately not a pd-btn: this row already carries note,
                   clear, attach and possibly declare. A quiet text line reads
                   as "there is more" without adding to that stack. -->
              <button class="pd-more-units" on:click|stopPropagation={() => showAllUnits = !showAllUnits}>
                {showAllUnits ? 'Show fewer' : `+${dispatch.units.length - UNIT_LIMIT} ${$Locale.additionals}`}
              </button>
            {/if}
          </div>
        </div>
      {/if}

      <div class="flex gap-[5px] mt-[8px]">
        <button class="pd-btn flex-1" on:click={noteOpen ? () => noteOpen = false : openNote}>
          <i class="fas fa-pen"></i> {dispatch.dispatchNote ? 'Edit note' : 'Add note'}
        </button>
        <button class="pd-btn {confirmClear ? 'pd-btn--red' : ''} flex-1" on:click={clearCall}>
          <i class="fas fa-{confirmClear ? 'triangle-exclamation' : 'circle-check'}"></i>
          {confirmClear ? 'Confirm clear' : 'Clear call'}
        </button>
      </div>

      {#if mayDeclare}
        <button class="pd-btn {isIncident ? 'pd-btn--red' : confirmDeclare ? 'pd-btn--red' : ''} w-full mt-[5px]" on:click|stopPropagation={toggleIncident}>
          {#if isIncident}
            <i class="fas fa-xmark"></i> Stand down major incident
          {:else if confirmDeclare}
            <i class="fas fa-triangle-exclamation"></i> Confirm — pins for all units
          {:else}
            <i class="fas fa-tower-broadcast"></i> Declare major incident
          {/if}
        </button>
      {/if}

      <button class="pd-btn {CheckIfAttached(dispatch.units, $PLAYER.citizenid) ? 'pd-btn--red' : 'pd-btn--green'} w-full mt-[5px]"
        on:click={() => {
          if (CheckIfAttached(dispatch.units, $PLAYER.citizenid)) {
            SendNUI("detachUnit", dispatch );
            SendNUI("refreshAlerts");
          } else {
            SendNUI("attachUnit", dispatch );
            SendNUI("refreshAlerts");
          }
        }}>
        {#if CheckIfAttached(dispatch.units, $PLAYER.citizenid)}
          <i class="fas fa-user-minus"></i> {$Locale.dispatch_detach}
        {:else}
          <i class="fas fa-user-plus"></i> {$Locale.dispatch_attach}
        {/if}
      </button>
    </div>
  {/if}
</div>