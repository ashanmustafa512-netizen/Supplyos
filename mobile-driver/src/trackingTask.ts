import * as TaskManager from "expo-task-manager";
import * as Location from "expo-location";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { supabase } from "./supabase";

export const LOCATION_TASK = "SUPPLYOS_WORK_SHIFT_LOCATION";
export const SHIFT_SESSION_KEY = "supplyos.activeEmployeeShiftSession";

TaskManager.defineTask(LOCATION_TASK, async ({ data, error }) => {
  if (error || !data) return;
  const sessionId = await AsyncStorage.getItem(SHIFT_SESSION_KEY);
  if (!sessionId) return;

  const payload = data as { locations?: Location.LocationObject[] };
  const latest = payload.locations?.[payload.locations.length - 1];
  if (!latest) return;

  const { latitude, longitude, accuracy } = latest.coords;
  const { error: rpcError } = await supabase.rpc("record_employee_location", {
    p_session_id: sessionId,
    p_latitude: latitude,
    p_longitude: longitude,
    p_accuracy_m: accuracy ?? null,
    p_recorded_at: new Date(latest.timestamp).toISOString(),
  });

  // The server remains the source of truth. A stale location is shown as stale
  // if the phone is offline or the GPS fix is rejected.
  if (rpcError) {
    console.warn("SupplyOS shift location was not accepted:", rpcError.message);
    if (/session is no longer active|no longer active/i.test(rpcError.message)) {
      try { await Location.stopLocationUpdatesAsync(LOCATION_TASK); } catch { /* task may already be stopped */ }
      await AsyncStorage.removeItem(SHIFT_SESSION_KEY);
    }
  }
});

export async function beginNativeLocationUpdates() {
  const foreground = await Location.requestForegroundPermissionsAsync();
  if (foreground.status !== "granted") {
    throw new Error("Location permission is required. Allow location access to start your work shift.");
  }

  const background = await Location.requestBackgroundPermissionsAsync();
  if (background.status !== "granted") {
    throw new Error("Allow background location in Android settings so your owner can see your location while the screen is locked.");
  }

  // Do not restart the native task when the app resumes or refreshes.
  if (await Location.hasStartedLocationUpdatesAsync(LOCATION_TASK)) return;

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
      notificationBody: "Location is shared with your factory owner during this active shift. Stop sharing when your shift ends.",
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
