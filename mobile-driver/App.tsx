import React, { useCallback, useEffect, useState } from 'react';
import { AppState, Alert, Pressable, SafeAreaView, ScrollView, StatusBar, StyleSheet, Text, TextInput, View } from 'react-native';
import { supabase } from './src/supabase';
import { beginNativeLocationUpdates, stopNativeLocationUpdates, AsyncStorage, SESSION_KEY, SHIFT_SESSION_KEY } from './src/trackingTask';

type Assignment = { load_id: string; load_no: string; load_status: string; truck_id: string; registration_no: string; display_name: string; driver_name: string; pass_status: string };
type ActiveTrip = { session_id: string; load_id: string; load_no: string; truck_id: string; registration_no: string };
type ActiveShift = { session_id: string; employee_name: string; started_at?: string };
const CONSENT_VERSION = 'supplyos-trip-location-consent-v1';
const SHIFT_CONSENT_VERSION = 'supplyos-work-shift-location-consent-v1';

export default function App() {
  const [email, setEmail] = useState(''); const [password, setPassword] = useState('');
  const [signedIn, setSignedIn] = useState(false); const [loading, setLoading] = useState(false);
  const [assignments, setAssignments] = useState<Assignment[]>([]); const [active, setActive] = useState<ActiveTrip | null>(null); const [activeShift, setActiveShift] = useState<ActiveShift | null>(null);
  const [message, setMessage] = useState('Sign in using your SupplyOS driver account.');

  const refresh = useCallback(async () => {
    const { data: sessionData } = await supabase.auth.getSession();
    setSignedIn(!!sessionData.session);
    if (!sessionData.session) return;
    const { data, error } = await supabase.rpc('get_my_tracking_assignments');
    if (error) { setMessage(error.message); return; }
    setAssignments((Array.isArray(data) ? data : []) as Assignment[]);
    const savedId = await AsyncStorage.getItem(SESSION_KEY);
    if (savedId) {
      const { data: sessions } = await supabase.from('dispatch_tracking_sessions').select('id,load_id,truck_id').eq('id', savedId).is('ended_at', null).maybeSingle();
      if (sessions) {
        const assignment = (Array.isArray(data) ? data : []).find((x: Assignment) => x.load_id === sessions.load_id);
        if (assignment) setActive({ session_id: savedId, load_id: assignment.load_id, load_no: assignment.load_no, truck_id: assignment.truck_id, registration_no: assignment.registration_no });
      } else { await AsyncStorage.removeItem(SESSION_KEY); setActive(null); }
    }
    const { data: shiftRows } = await supabase.from('employee_location_sessions').select('id,employee_name,started_at').is('ended_at', null).order('started_at', { ascending: false }).limit(1);
    const currentShift = shiftRows?.[0];
    if (currentShift) {
      await AsyncStorage.setItem(SHIFT_SESSION_KEY, currentShift.id);
      setActiveShift({ session_id: currentShift.id, employee_name: currentShift.employee_name, started_at: currentShift.started_at });
    } else { await AsyncStorage.removeItem(SHIFT_SESSION_KEY); setActiveShift(null); }
  }, []);
  useEffect(() => {
    void refresh();
    const subscription = AppState.addEventListener('change', state => { if (state === 'active') void refresh(); });
    const interval = setInterval(() => { if (active || activeShift) void refresh(); }, 30000);
    return () => { subscription.remove(); clearInterval(interval); };
  }, [active, activeShift, refresh]);

  async function signIn() {
    setLoading(true); setMessage('Signing in…');
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    setLoading(false);
    if (error) { setMessage(error.message); return; }
    setMessage('Signed in. Loading assigned trips…'); await refresh();
  }
  async function startTrip(item: Assignment) {
    Alert.alert('Start trip tracking?', `SupplyOS will share this phone's location with authorized factory dispatch for ${item.registration_no} while this trip is active. Tracking stops when you end the trip or the server marks it inactive. You can see the ongoing Android location notification.`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Agree & start', onPress: () => { void (async () => {
        setLoading(true);
        const { data, error } = await supabase.rpc('start_dispatch_tracking_trip', { p_load_id: item.load_id, p_consent_version: CONSENT_VERSION });
        if (error) { setLoading(false); setMessage(error.message); return; }
        const result = data as { session_id: string };
        await AsyncStorage.setItem(SESSION_KEY, result.session_id);
        try {
          await beginNativeLocationUpdates();
          setActive({ session_id: result.session_id, load_id: item.load_id, load_no: item.load_no, truck_id: item.truck_id, registration_no: item.registration_no });
          setMessage('Trip tracking is active. Keep the persistent Android notification visible; dispatch will show stale status if updates stop.');
        } catch (e) {
          await supabase.rpc('stop_dispatch_tracking_trip', { p_session_id: result.session_id, p_reason: 'location_permission_or_start_failed' });
          await AsyncStorage.removeItem(SESSION_KEY);
          setMessage(e instanceof Error ? e.message : 'Could not start background location.');
        }
        setLoading(false);
      })(); } },
    ]);
  }
  async function startShift() {
    Alert.alert('Start work-shift location sharing?', "SupplyOS will share this phone's location with authorized factory managers only while this shift is active. Location is not collected by this feature after you end the shift. Android shows a persistent location notification. You can stop sharing at any time.", [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Agree & start shift', onPress: () => { void (async () => {
        setLoading(true); setMessage('Starting shift location sharing…');
        const { data, error } = await supabase.rpc('start_employee_location_shift', { p_consent_version: SHIFT_CONSENT_VERSION });
        if (error) { setLoading(false); setMessage(error.message); return; }
        const result = data as { session_id: string; employee_name: string; started_at?: string };
        await AsyncStorage.setItem(SHIFT_SESSION_KEY, result.session_id);
        try {
          await beginNativeLocationUpdates('shift');
          setActiveShift({ session_id: result.session_id, employee_name: result.employee_name, started_at: result.started_at });
          setMessage('Work-shift location sharing is active. Stop sharing when your shift ends.');
        } catch (e) {
          await supabase.rpc('stop_employee_location_shift', { p_session_id: result.session_id, p_reason: 'location_permission_or_start_failed' });
          await AsyncStorage.removeItem(SHIFT_SESSION_KEY);
          setMessage(e instanceof Error ? e.message : 'Could not start background location.');
        }
        setLoading(false);
      })(); } },
    ]);
  }
  async function endShift(reason = 'employee_stopped') {
    if (!activeShift) return;
    setLoading(true); await stopNativeLocationUpdates();
    const { error } = await supabase.rpc('stop_employee_location_shift', { p_session_id: activeShift.session_id, p_reason: reason });
    await AsyncStorage.removeItem(SHIFT_SESSION_KEY); setActiveShift(null); setLoading(false);
    setMessage(error ? `Phone tracking stopped, but the server could not close the shift: ${error.message}. Contact your manager.` : 'Shift location sharing stopped. No new positions will be sent for this shift.');
  }
  async function endTrip(reason = 'driver_stopped') {
    if (!active) return;
    setLoading(true);
    await stopNativeLocationUpdates();
    const { error } = await supabase.rpc('stop_dispatch_tracking_trip', { p_session_id: active.session_id, p_reason: reason });
    await AsyncStorage.removeItem(SESSION_KEY); setActive(null); setLoading(false);
    setMessage(error ? `Phone tracking stopped, but the server could not close the session: ${error.message}. Contact dispatch.` : 'Trip tracking stopped. Your last position remains available with its timestamp.');
    await refresh();
  }
  async function signOut() { if (active) await endTrip('driver_signed_out'); if (activeShift) await endShift('employee_signed_out'); await supabase.auth.signOut(); setSignedIn(false); setAssignments([]); }

  return <SafeAreaView style={styles.safe}><StatusBar barStyle="light-content" backgroundColor="#0b1220" /><ScrollView contentContainerStyle={styles.container}>
    <View style={styles.brand}><Text style={styles.kicker}>SUPPLYOS FLEET</Text><Text style={styles.title}>SupplyOS employee</Text><Text style={styles.subtitle}>Start location sharing only when your work shift or assigned delivery trip begins. Stop it when work ends.</Text></View>
    {!signedIn ? <View style={styles.card}><Text style={styles.heading}>Employee sign in</Text><TextInput style={styles.input} autoCapitalize="none" keyboardType="email-address" placeholder="Email" placeholderTextColor="#8792a8" value={email} onChangeText={setEmail} /><TextInput style={styles.input} secureTextEntry placeholder="Password" placeholderTextColor="#8792a8" value={password} onChangeText={setPassword} /><Button title="Sign in" disabled={loading || !email.trim() || !password} onPress={() => void signIn()} /><Text style={styles.muted}>{message}</Text></View> : <>
      {active ? <View style={[styles.card, styles.activeCard]}><Text style={styles.pill}>TRIP TRACKING ACTIVE</Text><Text style={styles.heading}>{active.registration_no}</Text><Text style={styles.body}>{active.load_no}</Text><Text style={styles.muted}>Background GPS is enabled. Keep the Android foreground-service notification active. Location depends on device settings, GPS signal, battery controls and network coverage.</Text><Button title="End trip & stop sharing" danger onPress={() => void endTrip()} disabled={loading} /></View> : activeShift ? <View style={[styles.card, styles.activeCard]}><Text style={styles.pill}>WORK-SHIFT LOCATION ACTIVE</Text><Text style={styles.heading}>{activeShift.employee_name}</Text><Text style={styles.body}>Your current position is shared with authorized factory managers during this active shift only.</Text><Text style={styles.muted}>Keep the Android location notification visible. GPS accuracy, internet coverage and battery settings affect freshness on the manager map.</Text><Button title="End shift & stop sharing" danger onPress={() => void endShift()} disabled={loading} /></View> : <><View style={styles.card}><Text style={styles.heading}>Employee shift location</Text><Text style={styles.muted}>For factory employees using company-provided phones. Location sharing starts only after you read the notice and tap Agree & start shift. Stop it when work ends.</Text><Button title="Agree & start shift location" onPress={() => void startShift()} disabled={loading} /></View><View style={styles.card}><Text style={styles.heading}>Assigned trips</Text><Text style={styles.muted}>Only in-transit loads with a cleared truck inspection pass are available.</Text>{assignments.length === 0 ? <Text style={styles.body}>No eligible assigned trip. Ask dispatch to assign your driver account to the truck, complete inspection, and dispatch the load.</Text> : assignments.map(item => <View key={item.load_id} style={styles.trip}><Text style={styles.heading}>{item.registration_no}</Text><Text style={styles.body}>{item.load_no} · {item.display_name}</Text><Text style={styles.muted}>Inspection pass: {item.pass_status}</Text><Button title="Agree & start tracking" onPress={() => startTrip(item)} disabled={loading || item.pass_status !== 'cleared'} /></View>)}</View></>}
      <Button title="Refresh assigned trips" secondary onPress={() => void refresh()} disabled={loading || !!active} /><Button title="Sign out" secondary onPress={() => void signOut()} disabled={loading} />
    </>}
    <View style={styles.privacy}><Text style={styles.privacyTitle}>Location privacy</Text><Text style={styles.muted}>Signing in never starts location collection. Employee location is shared only during a shift you explicitly start; delivery tracking is limited to an authorized trip. End sharing when work or the trip ends. Authorized factory managers can see the last received position and whether it is stale. Ask your manager about the factory's written purpose, access and retention policy.</Text></View>
  </ScrollView></SafeAreaView>;
}
function Button({ title, onPress, disabled, secondary, danger }: { title: string; onPress: () => void; disabled?: boolean; secondary?: boolean; danger?: boolean }) {
  return <Pressable onPress={onPress} disabled={disabled} style={[styles.button, secondary && styles.secondaryButton, danger && styles.dangerButton, disabled && styles.disabled]}><Text style={[styles.buttonText, secondary && styles.secondaryText]}>{title}</Text></Pressable>;
}
const styles = StyleSheet.create({ safe: { flex: 1, backgroundColor: '#0b1220' }, container: { padding: 20, gap: 14, paddingBottom: 36 }, brand: { paddingVertical: 12 }, kicker: { color: '#60a5fa', fontWeight: '800', letterSpacing: 2, fontSize: 12 }, title: { color: '#f8fafc', fontSize: 32, fontWeight: '800', marginTop: 8 }, subtitle: { color: '#aab6c9', fontSize: 15, lineHeight: 22, marginTop: 8 }, card: { backgroundColor: '#141e30', borderColor: '#2b3950', borderWidth: 1, borderRadius: 16, padding: 18, gap: 12 }, activeCard: { borderColor: '#2d9875' }, heading: { color: '#f8fafc', fontSize: 18, fontWeight: '800' }, body: { color: '#e2e8f0', fontSize: 15, lineHeight: 22 }, muted: { color: '#aab6c9', fontSize: 13, lineHeight: 19 }, input: { backgroundColor: '#0b1220', borderColor: '#334155', borderWidth: 1, borderRadius: 10, padding: 13, color: '#f8fafc' }, button: { backgroundColor: '#3b82f6', padding: 14, borderRadius: 10, alignItems: 'center', marginTop: 2 }, buttonText: { color: '#fff', fontWeight: '800' }, secondaryButton: { backgroundColor: 'transparent', borderColor: '#41516b', borderWidth: 1 }, secondaryText: { color: '#e2e8f0' }, dangerButton: { backgroundColor: '#b91c1c' }, disabled: { opacity: 0.45 }, trip: { paddingVertical: 12, borderTopColor: '#2b3950', borderTopWidth: 1, gap: 8 }, pill: { color: '#6ee7b7', fontSize: 11, fontWeight: '900', letterSpacing: 1.4 }, privacy: { padding: 14, gap: 8 }, privacyTitle: { color: '#f8fafc', fontWeight: '800' } });
