"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { MapPinned, ShieldCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

type ShiftSession = { id: string; started_at: string };

const CONSENT_VERSION = "supplyos-manager-work-shift-location-consent-v1";

export function ManagerShiftLocation() {
  const supabase = useMemo(() => createClient(), []);
  const [session, setSession] = useState<ShiftSession | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("Checking your work-shift location status…");
  const [lastUpdate, setLastUpdate] = useState<string | null>(null);
  const watchId = useRef<number | null>(null);
  const sessionIdRef = useRef<string | null>(null);
  const lastSentAt = useRef(0);

  const stopWatching = useCallback(() => {
    if (watchId.current !== null && typeof navigator !== "undefined" && navigator.geolocation) {
      navigator.geolocation.clearWatch(watchId.current);
      watchId.current = null;
    }
  }, []);

  const recordPosition = useCallback(async (sessionId: string, position: GeolocationPosition) => {
    const { latitude, longitude, accuracy } = position.coords;
    const { error } = await supabase.rpc("record_employee_location", {
      p_session_id: sessionId,
      p_latitude: latitude,
      p_longitude: longitude,
      p_accuracy_m: Number.isFinite(accuracy) ? accuracy : null,
      p_recorded_at: new Date(position.timestamp).toISOString(),
    });
    if (error) {
      setMessage(`Location update not accepted: ${error.message}`);
      if (/no longer active|not active/i.test(error.message)) {
        stopWatching();
        sessionIdRef.current = null;
        setSession(null);
      }
      return;
    }
    setLastUpdate(new Date().toISOString());
    setMessage("Your manager work-shift location is being shared with the owner.");
  }, [supabase, stopWatching]);

  const beginWatching = useCallback((sessionId: string) => {
    if (!navigator.geolocation) {
      setMessage("This device or browser does not support location sharing.");
      return;
    }
    stopWatching();
    watchId.current = navigator.geolocation.watchPosition(
      position => {
        const now = Date.now();
        if (now - lastSentAt.current < 15000) return;
        lastSentAt.current = now;
        void recordPosition(sessionId, position);
      },
      error => {
        const reason = error.code === error.PERMISSION_DENIED
          ? "Location permission was denied. Enable location access for SupplyOS to continue."
          : error.code === error.POSITION_UNAVAILABLE
            ? "The device cannot get a GPS fix. Check location services and try again."
            : "The location request timed out. SupplyOS will keep showing the last update as stale.";
        setMessage(reason);
      },
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 20000 },
    );
  }, [recordPosition, stopWatching]);

  useEffect(() => {
    let alive = true;
    const { data: authListener } = supabase.auth.onAuthStateChange(event => {
      if (event === "SIGNED_OUT") {
        stopWatching();
        sessionIdRef.current = null;
        setSession(null);
      }
    });

    async function loadActiveShift() {
      setLoading(true);
      const { data: authData } = await supabase.auth.getUser();
      if (!authData.user) {
        if (alive) { setSession(null); setLoading(false); }
        return;
      }
      const { data, error } = await supabase
        .from("employee_location_sessions")
        .select("id,started_at")
        .eq("user_id", authData.user.id)
        .is("ended_at", null)
        .order("started_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!alive) return;
      if (error) {
        setMessage(error.message);
      } else if (data) {
        setSession({ id: data.id, started_at: data.started_at });
        sessionIdRef.current = data.id;
        setMessage("An active work shift was found. Reconnecting location updates…");
        beginWatching(data.id);
      } else {
        setSession(null);
        sessionIdRef.current = null;
        setMessage("Start your work shift to share your current location with the owner.");
      }
      setLoading(false);
    }
    void loadActiveShift();
    return () => {
      alive = false;
      authListener.subscription.unsubscribe();
      stopWatching();
    };
  }, [beginWatching, stopWatching, supabase]);

  function requestCurrentPosition(): Promise<GeolocationPosition> {
    return new Promise((resolve, reject) => {
      if (!navigator.geolocation) {
        reject(new Error("This device or browser does not support location sharing."));
        return;
      }
      navigator.geolocation.getCurrentPosition(
        resolve,
        error => reject(new Error(error.code === error.PERMISSION_DENIED
          ? "Location permission is required. Allow location access for SupplyOS."
          : "Could not get a fresh GPS fix. Turn on device location and try again.")),
        { enableHighAccuracy: true, maximumAge: 0, timeout: 20000 },
      );
    });
  }

  async function startShift() {
    setBusy(true);
    setMessage("Requesting location permission…");
    try {
      const position = await requestCurrentPosition();
      const { data, error } = await supabase.rpc("start_employee_location_shift", {
        p_consent_version: CONSENT_VERSION,
      });
      if (error) throw error;
      const result = data as { session_id: string; started_at: string };
      sessionIdRef.current = result.session_id;
      setSession({ id: result.session_id, started_at: result.started_at });
      await recordPosition(result.session_id, position);
      lastSentAt.current = Date.now();
      beginWatching(result.session_id);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Could not start your work-shift location.");
    } finally {
      setBusy(false);
    }
  }

  async function endShift() {
    const currentId = sessionIdRef.current;
    if (!currentId) return;
    setBusy(true);
    stopWatching();
    const { error } = await supabase.rpc("stop_employee_location_shift", {
      p_session_id: currentId,
      p_reason: "manager_stopped",
    });
    if (error) {
      setMessage(`Location updates stopped on this screen, but the server could not close the shift: ${error.message}`);
      setBusy(false);
      return;
    }
    setSession(null);
    sessionIdRef.current = null;
    lastSentAt.current = 0;
    setLastUpdate(null);
    setMessage("Work shift ended. No new manager location updates will be sent.");
    setBusy(false);
  }

  return (
    <section className="panel" style={{ marginBottom: 20 }}>
      <div className="panel-heading">
        <div><h2><MapPinned size={17} style={{ display: "inline", marginRight: 8 }}/>Manager work-shift location</h2><p>Enable location when you open the Manager app so the owner can see your current position while you work.</p></div>
        <span className="panel-heading-icon"><ShieldCheck size={17}/></span>
      </div>
      <div className="page-heading-row" style={{ alignItems: "center" }}>
        <div>
          <strong>{loading ? "Checking location…" : session ? "Location sharing active" : "Location sharing not started"}</strong>
          <p>{message}</p>
          {session && <p className="helper-line">Shift started {new Date(session.started_at).toLocaleString()}{lastUpdate ? ` · Last GPS update ${new Date(lastUpdate).toLocaleTimeString()}` : ""}</p>}
        </div>
        {session
          ? <div className="row-actions"><button className="button button-secondary" type="button" onClick={() => beginWatching(session.id)} disabled={busy || loading}>Retry location</button><button className="button button-secondary" type="button" onClick={() => void endShift()} disabled={busy || loading}>End shift & stop sharing</button></div>
          : <button className="button button-primary" type="button" onClick={() => void startShift()} disabled={busy || loading}>{busy ? "Enabling…" : "Enable location & start shift"}</button>}
      </div>
      <p className="helper-line">Location is collected only during the shift you start here. Mobile browser tracking may pause when the Manager app is backgrounded; the owner map will mark an old update as stale.</p>
    </section>
  );
}
