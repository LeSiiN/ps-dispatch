<script>
  // One call in a dispatch panel: compact row, expandable in place to the
  // full section anatomy (map thumb, location/vehicle strips, danger banner,
  // person line, note, units, attach button). Extracted from Menu.svelte so
  // the pending list and the Active Calls board share one implementation.
  import { createEventDispatcher } from 'svelte';
  import { slide } from 'svelte/transition';
  import { DUR, EASE_OUT } from '@utils/motion';
  import { PLAYER, Locale, MAP_IMAGE, UNATTENDED_AFTER, PINNED_CODES, THUMBS_ENABLED } from '@store/stores';
  import { timeAgo } from '@utils/timeAgo';
  import { SendNUI } from '@utils/SendNUI';
  import MapThumb from './MapThumb.svelte';

  export let dispatch;              // the call
  export let expanded = false;      // parent-controlled (one open at a time)
  export let showUnitsInline = false; // Active board: callsigns in the row

  const emit = createEventDispatcher();
  let showAllUnits = false;
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
  <button class="pd-row {dispatch.priority == 1 ? 'pd-row--priority' : ''}" class:pd-row--open={expanded} on:click={() => emit('toggle')}>
    <div class="pd-icon {dispatch.priority == 1 ? 'pd-icon--priority' : ''}">
      <i class={dispatch.icon}></i>
    </div>
    <div class="flex flex-col min-w-0 flex-1 gap-[2px]">
      <div class="flex items-center gap-[6px]">
        {#if $PINNED_CODES.includes(dispatch.codeName)}
          <span class="pd-badge pd-badge--red" title="Pinned critical call"><i class="fas fa-thumbtack"></i></span>
        {/if}
        <span class="pd-badge {dispatch.priority == 1 ? 'pd-badge--red' : 'pd-badge--cyan'}">{dispatch.code}</span>
        {#if (dispatch.count || 1) > 1}
          <span class="pd-badge pd-badge--red">×{dispatch.count}</span>
        {/if}
        {#if dispatch.hotspot}
          <span class="pd-badge pd-badge--purple" title="Repeated incidents on this street"><i class="fas fa-fire mr-[3px]"></i>×{dispatch.hotspot}</span>
        {/if}
        <span class="pd-row-msg flex-1">{dispatch.message}</span>
      </div>
      <div class="flex items-center gap-[8px]">
        <span class="pd-kv-label">#{dispatch.id}</span>
        {#if dispatch.street}<span class="text-[10px] opacity-40 truncate">{dispatch.street}</span>{/if}
        <span class="pd-time">{timeAgo(dispatch.time)}</span>
      </div>
      {#if showUnitsInline && dispatch.units?.length}
        <div class="flex items-center gap-[4px] flex-wrap">
          {#each dispatch.units.slice(0, 4) as unit}
            <span class="pd-badge {unit.job.type == "leo" ? "pd-badge--blue" : unit.job.type == "ems" ? "pd-badge--red" : ""} pd-mono">{unit.metadata.callsign || unit.charinfo.lastname}</span>
          {/each}
          {#if dispatch.units.length > 4}
            <span class="pd-badge">+{dispatch.units.length - 4}</span>
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
      {#if $MAP_IMAGE && $THUMBS_ENABLED}
        <!-- Click opens the enlarged, zoomable map (handled by the parent so
             there is only ever one overlay). -->
        <div class="pd-thumb-click" title="Enlarge map" on:click={() => emit('expandMap')}>
          <MapThumb coords={dispatch.displayCoords || dispatch.coords} radius={dispatch.mapRadius || 0} priority={dispatch.priority} src={$MAP_IMAGE} height={92} />
          <span class="pd-thumb-zoom"><i class="fas fa-magnifying-glass-plus"></i></span>
        </div>
      {/if}
      {#if dispatch.street || dispatch.heading}
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
            <span class="pd-strip-title">{dispatch.vehicle || 'Unknown vehicle'}</span>
            {#if dispatch.plate}
              <span class="pd-plate">{dispatch.plate}</span>
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
        <div class="pd-danger {dispatch.automaticGunFire ? 'pd-danger--red' : ''}">
          <i class="fas fa-gun"></i>
          <span>
            {#if dispatch.weapon}{dispatch.weapon}{:else}Shots fired{/if}
            {#if dispatch.automaticGunFire}&nbsp;· Automatic fire{/if}
          </span>
        </div>
      {/if}

      {#if personLine(dispatch).length}
        <div class="pd-person">
          <i class="fas fa-user"></i>
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
            {#each dispatch.units.slice(0, showAllUnits ? dispatch.units.length : 3) as unit}
              <div class="pd-unit">
                {#if unit.metadata.callsign}<span class="pd-badge pd-mono">{unit.metadata.callsign}</span>{/if}
                <span class="pd-badge {unit.job.type == "leo" ? "pd-badge--blue" : unit.job.type == "ems" ? "pd-badge--red" : ""} uppercase">{unit.job.name}</span>
                <span class="truncate">{unit.charinfo.firstname} {unit.charinfo.lastname}</span>
              </div>
            {/each}
            {#if dispatch.units.length > 3 && !showAllUnits}
              <button class="pd-btn w-full mt-[4px]" on:click={() => showAllUnits = true}>
                +{dispatch.units.length - 3} {$Locale.additionals}
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
