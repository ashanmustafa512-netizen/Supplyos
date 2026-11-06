import * as TaskManager from 'expo-task-manager';
import * as Location from 'expo-location';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { supabase } from './supabase';

export const LOCATION_TASK = 'SUPPLYOS_ACTIVE_TRIP_LOCATION';
const SESSION_KEY = 'supplyos.activeTrackingSession';
export const SHIFT_SESSION_KEY = 'supplyos.activeEmployeeShiftSession';

TaskManager.defineTask(LOCATION_TASK, async ({ data, error }) => {
  if (error || !data) return;
  const shiftSessionId = await AsyncStorage.getItem(SHIFT_SESSION_KEY);
  const sessionId = shiftSessionId ? null : await AsyncStorage.getItem(SESSION_KEY);
  if (!shiftSessionId && !sessionId) return;
  const payload = data as { locations?: Location.LocationObject[] };
  const points = payload.locations ?? [];
  const latest = points[points.length - 1];
  if (!latest) return;
  const { latitude, longitude, accuracy } = latest.coords;
  const { error: rpcError } = shiftSessionId
    ? await supabase.rpc('record_employee_location', { p_session_id: shiftSessionId, p_latitude: latitude, p_longitude: longitude, p_accuracy_m: accuracy ?? null, p_recorded_at: new Date(latest.timestamp).toISOString() })
    : await supabase.rpc('record_dispatch_tracking_location', { p_session_id: sessionId, p_latitude: latitude, p_longitude: longitude, p_accuracy_m: accuracy ?? null, p_recorded_at: new Date(latest.timestamp).toISOString() });
  // No local claim of success: if network drops, the server timestamp remains stale
  // and dispatch will show that truth. Expo will retry on a later location callback.
  if (rpcError) {
    console.warn('SupplyOS location was not accepted; dispatch will show stale status.', rpcError.message);
    // A temporary network failure should not end a trip. Stop only when the server
    // explicitly reports that the authorization/session/trip is no longer valid.
    if (/no longer active|no longer in transit|assignment is no longer active/i.test(rpcError.message)) {
      try { await Location.stopLocationUpdatesAsync(LOCATION_TASK); } catch { /* task may already be stopped */ }
      await AsyncStorage.removeItem(SHIFT_SESSION_KEY);
      await AsyncStorage.removeItem(SESSION_KEY);
    }
  }
});

export async function beginNativeLocationUpdates(mode: 'trip' | 'shift' = 'trip') {
  const foreground = await Location.requestForegroundPermissionsAsync();
  if (foreground.status !== 'granted') throw new Error('Location permission is required to start trip tracking.');
  const background = await Location.requestBackgroundPermissionsAsync();
  if (background.status !== 'granted') throw new Error('Allow background location in Android settings so tracking continues when the screen is locked.');
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
      notificationTitle: mode === 'shift' ? 'SupplyOS work-shift location is active' : 'SupplyOS trip tracking is active',
      notificationBody: mode === 'shift' ? 'Location is shared with authorized factory managers during your active work shift. Stop sharing when your shift ends.' : 'Location is shared with authorized factory dispatch during this trip.',
      notificationColor: '#0B1220',
      killServiceOnDestroy: false,
    },
  });
}

export async function stopNativeLocationUpdates() {
  if (await Location.hasStartedLocationUpdatesAsync(LOCATION_TASK)) {
    await Location.stopLocationUpdatesAsync(LOCATION_TASK);
  }
}

export { AsyncStorage, SESSION_KEY };
