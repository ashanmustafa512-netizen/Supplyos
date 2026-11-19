import * as TaskManager from "expo-task-manager";
import * as Location from "expo-location";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { supabase } from "./supabase";

export const LOCATION_TASK = "SUPPLYOS_ACTIVE_SHIFT_LOCATION";
export const SHIFT_SESSION_KEY = "supplyos.activeEmployeeShiftSession";
const LEGACY_TRIP_SESSION_KEY = "supplyos.activeTrackingSession";

TaskManager.defineTask(LOCATION_TASK, async ({ data, error }) => {
  if (error || !data) return;
  const shiftSessionId = await AsyncStorage.getItem(SHIFT_SESSION_KEY);
  if (!shiftSessionId) {
    // Retire any background trip task left behind by an older app version.
    try {
      if (await Location.hasStartedLocationUpdatesAsync(LOCATION_TASK)) {
        await Location.stopLocationUpdatesAsync(LOCATION_TASK);
      }
    } catch { /* task may already be stopped */ }
    await AsyncStorage.removeItem(LEGACY_TRIP_SESSION_KEY);
    return;
  }

  const payload = data as { locations?: Location.LocationObject[] };
  const points = payload.locations ?? [];
  const latest = points[points.length - 1];
  if (!latest) return;
  const { latitude, longitude, accuracy } = latest.coords;
  const { error: rpcError } = await supabase.rpc("record_employee_location", {
    p_session_id: shiftSessionId,
    p_latitude: latitude,
    p_longitude: longitude,
    p_accuracy_m: accuracy ?? null,
    p_recorded_at: new Date(latest.timestamp).toISOString(),
  });

  if (rpcError) {
    console.warn("SupplyOS shift location was not accepted; the owner map will show stale status.", rpcError.message);
    if (/no longer active|session.*not found|permission/i.test(rpcError.message)) {
      try { await Location.stopLocationUpdatesAsync(LOCATION_TASK); } catch { /* task may already be stopped */ }
      await AsyncStorage.removeItem(SHIFT_SESSION_KEY);
    }
  }
});

export async function beginNativeLocationUpdates(_mode: "shift" = "shift") {
  const foreground = await Location.requestForegroundPermissionsAsync();
  if (foreground.status !== "granted") throw new Error("Location permission is required to start work-shift sharing.");
  const background = await Location.requestBackgroundPermissionsAsync();
  if (background.status !== "granted") throw new Error("Allow background location in Android settings so sharing continues when the screen is locked.");
  const already = await TaskManager.isTaskRegisteredAsync(LOCATION_TASK);
  if (already) await Location.stopLocationUpdatesAsync(LOCATION_TASK);
  await Location.startLocationUpdatesAsync(LOCATION_TASK, {
    accuracy: Location.Accuracy.High,
    timeInterval: 15000,
    distanceInterval: 25,
    deferredUpdatesInterval: 15000,
    deferredUpdatesDistance: 25,
    pausesUpdatesAutomatically: false,
    showsBackgroundLocationIndicator: true,
    foregroundService: {
      notificationTitle: "SupplyOS work-shift location is active",
      notificationBody: "Location is shared with authorized factory owners during your active work shift. Stop sharing when your shift ends.",
      notificationColor: "#0B1220",
      killServiceOnDestroy: false,
    },
  });
}

export async function stopNativeLocationUpdates() {
  if (await Location.hasStartedLocationUpdatesAsync(LOCATION_TASK)) {
    await Location.stopLocationUpdatesAsync(LOCATION_TASK);
  }
}

export { AsyncStorage };
