<script>
  import { PLAYER, Locale, DISPATCH_MENU, DISPATCH_MUTED, DISPATCH_DISABLED, MAP_IMAGE, UNATTENDED_AFTER, processedDispatchMenu } from '@store/stores';
  import { fly, slide } from 'svelte/transition';
	import { timeAgo } from '@utils/timeAgo'
	import { SendNUI } from '@utils/SendNUI'
	import MapThumb from './MapThumb.svelte'
  
  let activeCallId = null;
  let additionalUnitsVisible = {};

  function toggleDispatch(id) {
    if (activeCallId === id) {
      activeCallId = null;
    } else {
      activeCallId = id;
    }
  }

  function CheckIfAttached(units, player) {
    for (let i = 0; i < units.length; i++) {
      if (units[i].citizenid === player) {
        return true;
      }
    }
    return false;
  }

  function toggleAdditionalUnits(callId) {
    additionalUnitsVisible[callId] = !additionalUnitsVisible[callId];
  }

  function getAdditionalUnitsCount(dispatch) {
    const maxVisibleUnits = 3;
    const additionalUnits = dispatch.units.length - maxVisibleUnits;
    return Math.max(0, additionalUnits);
  }

  function toggleMute() {
    DISPATCH_MUTED.update(value => !value);
    SendNUI("toggleMute", { boolean: $DISPATCH_MUTED });
  }

  function toggleAlerts() {
    DISPATCH_DISABLED.update(value => !value);
    SendNUI("toggleAlerts", { boolean: $DISPATCH_DISABLED });
  }

  // Same section helpers as the alert card — the expanded call shows the
  // identical anatomy (location strip, vehicle strip, danger banner, person
  // line, quoted note) so alert and menu read as one product.
  // Triage: true when nobody is attached and the call has been waiting
  // longer than Config.UnattendedAfter minutes.
  function unattendedFor(d) {
    if (!$UNATTENDED_AFTER) return 0;
    if ((d.units?.length || 0) > 0) return 0;
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

<div class="w-screen h-screen flex items-center justify-end" transition:fly="{{ x: 400 }}">
  <!-- One contained MDT-style panel: header with title + controls, scrollable
       list of compact call rows that expand in place. -->
  <div class="pd-panel w-[370px] max-w-[30vw] h-[86%] mr-[14px]">

    <div class="pd-head">
      <div class="pd-icon"><i class="fas fa-tower-broadcast"></i></div>
      <span class="pd-title">Dispatch</span>
      {#if $DISPATCH_MENU}
        <span class="pd-badge">{$processedDispatchMenu.length} active</span>
      {/if}
      <div class="flex items-center gap-[4px] ml-auto">
        <button class="pd-ctl" title="Refresh" on:click={() => SendNUI("refreshAlerts")}>
          <i class="fas fa-arrows-rotate"></i>
        </button>
        <button class="pd-ctl" class:pd-ctl--active={$DISPATCH_MUTED} title="Mute sounds" on:click={toggleMute}>
          <i class="fas fa-volume-{$DISPATCH_MUTED ? "xmark" : "high"}"></i>
        </button>
        <button class="pd-ctl" class:pd-ctl--active={$DISPATCH_DISABLED} title="Toggle alerts" on:click={toggleAlerts}>
          <i class="fas fa-{$DISPATCH_DISABLED ? "bell-slash" : "bell"}"></i>
        </button>
        <button class="pd-ctl" title="Clear blips" on:click={() => SendNUI("clearBlips")}>
          <i class="fas fa-ban"></i>
        </button>
      </div>
    </div>

    <div class="pd-scroll flex-1 overflow-y-auto p-[10px] flex flex-col gap-[6px]">
      {#if $DISPATCH_MENU}
        {#each $processedDispatchMenu as dispatch (dispatch.id)}
          <div>
            <button class="pd-row {dispatch.priority == 1 ? 'pd-row--priority' : ''}" class:pd-row--open={activeCallId === dispatch.id} on:click={() => toggleDispatch(dispatch.id)}>
              <div class="pd-icon {dispatch.priority == 1 ? 'pd-icon--priority' : ''}">
                <i class={dispatch.icon}></i>
              </div>
              <div class="flex flex-col min-w-0 flex-1 gap-[2px]">
                <div class="flex items-center gap-[6px]">
                  <span class="pd-badge {dispatch.priority == 1 ? 'pd-badge--red' : 'pd-badge--cyan'}">{dispatch.code}</span>
                  {#if (dispatch.count || 1) > 1}
                    <span class="pd-badge pd-badge--red">×{dispatch.count}</span>
                  {/if}
                  <span class="pd-row-msg flex-1">{dispatch.message}</span>
                </div>
                <div class="flex items-center gap-[8px]">
                  <span class="pd-kv-label">#{dispatch.id}</span>
                  {#if dispatch.street}<span class="text-[10px] opacity-40 truncate">{dispatch.street}</span>{/if}
                  <span class="pd-time">{timeAgo(dispatch.time)}</span>
                </div>
              </div>
              <div class="flex items-center gap-[6px] flex-shrink-0">
                {#if unattendedFor(dispatch)}
                  <span class="pd-badge pd-badge--amber" title="No units attached"><i class="fas fa-clock mr-[3px]"></i>{unattendedFor(dispatch)}m</span>
                {/if}
                {#if dispatch.units.length > 0}
                  <span class="pd-badge pd-badge--green"><i class="fas fa-user-group mr-[3px]"></i>{dispatch.units.length}</span>
                {/if}
                <i class="fas fa-chevron-{activeCallId === dispatch.id ? 'up' : 'down'} text-[9px] opacity-35"></i>
              </div>
            </button>

            {#if activeCallId === dispatch.id}
              <div class="pd-detail" transition:slide={{ duration: 200 }}>
                {#if $MAP_IMAGE}
                  <MapThumb coords={dispatch.coords} priority={dispatch.priority} src={$MAP_IMAGE} height={92} />
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

                {#if dispatch.units.length > 0}
                  <div class="mt-[7px]">
                    <span class="pd-kv-label">Attached Units</span>
                    <div class="mt-[3px]">
                      {#each dispatch.units.slice(0, additionalUnitsVisible[dispatch.id] ? dispatch.units.length : 3) as unit}
                        <div class="pd-unit">
                          {#if unit.metadata.callsign}<span class="pd-badge pd-mono">{unit.metadata.callsign}</span>{/if}
                          <span class="pd-badge {unit.job.type == "leo" ? "pd-badge--blue" : unit.job.type == "ems" ? "pd-badge--red" : ""} uppercase">{unit.job.name}</span>
                          <span class="truncate">{unit.charinfo.firstname} {unit.charinfo.lastname}</span>
                        </div>
                      {/each}
                      {#if dispatch.units.length > 3 && !additionalUnitsVisible[dispatch.id]}
                        <button class="pd-btn w-full mt-[4px]" on:click={() => toggleAdditionalUnits(dispatch.id)}>
                          +{getAdditionalUnitsCount(dispatch)} {$Locale.additionals}
                        </button>
                      {/if}
                    </div>
                  </div>
                {/if}

                <button class="pd-btn {CheckIfAttached(dispatch.units, $PLAYER.citizenid) ? 'pd-btn--red' : 'pd-btn--green'} w-full mt-[8px]"
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
        {/each}
      {/if}
    </div>
  </div>
</div>
