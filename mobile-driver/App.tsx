import React, { useCallback, useEffect, useState } from "react";
import { Alert, AppState, Pressable, SafeAreaView, ScrollView, StatusBar, StyleSheet, Text, TextInput, View } from "react-native";
import { supabase } from "./src/supabase";
import { AsyncStorage, SHIFT_SESSION_KEY, beginNativeLocationUpdates, stopNativeLocationUpdates } from "./src/trackingTask";

type ActiveShift = { session_id: string; employee_name: string; started_at: string };

const CONSENT_VERSION = "supplyos-work-shift-location-consent-v1";

export default function App() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [signedIn, setSignedIn] = useState(false);
  const [loading, setLoading] = useState(false);
  const [activeShift, setActiveShift] = useState<ActiveShift | null>(null);
  const [tracking, setTracking] = useState(false);
  const [message, setMessage] = useState("Sign in with your SupplyOS manager or employee account.");

  const refresh = useCallback(async () => {
    const { data } = await supabase.auth.getSession();
    setSignedIn(!!data.session);
    if (!data.session) return;
    const { data: rows, error } = await supabase
      .from("employee_location_sessions")
      .select("id,employee_name,started_at")
      .eq("user_id", data.session.user.id)
      .is("ended_at", null)
      .order("started_at", { ascending: false })
      .limit(1);
    if (error) { setMessage(error.message); return; }
    const row = rows?.[0];
    if (row) {
      await AsyncStorage.setItem(SHIFT_SESSION_KEY, row.id);
      setActiveShift({ session_id: row.id, employee_name: row.employee_name, started_at: row.started_at });
    } else {
      await stopNativeLocationUpdates();
      await AsyncStorage.removeItem(SHIFT_SESSION_KEY);
      setActiveShift(null);
      setTracking(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
    const subscription = AppState.addEventListener("change", state => {
      if (state === "active") void refresh();
    });
    return () => subscription.remove();
  }, [refresh]);

  async function signIn() {
    setLoading(true); setMessage("Signing in…");
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) { setMessage(error.message); setLoading(false); return; }
    await refresh();
    setMessage("Signed in. Start your work shift when you are ready.");
    setLoading(false);
  }

  async function startShift() {
    Alert.alert(
      "Start work-shift location sharing?",
      "SupplyOS will share this phone's location with authorized factory owners only while this shift is active. Location is not collected by this feature after you end the shift. Android displays a persistent location notification. You can stop sharing at any time.",
      [
        { text: "Cancel", style: "cancel" },
        { text: "Agree & start shift", onPress: () => { void (async () => {
          setLoading(true); setMessage("Starting shift location sharing…");
          const { data, error } = await supabase.rpc("start_employee_location_shift", { p_consent_version: CONSENT_VERSION });
          if (error) { setMessage(error.message); setLoading(false); return; }
          const result = data as { session_id: string; employee_name: string; started_at: string };
          await AsyncStorage.setItem(SHIFT_SESSION_KEY, result.session_id);
          try {
            await beginNativeLocationUpdates("shift");
            setActiveShift({ session_id: result.session_id, employee_name: result.employee_name, started_at: result.started_at });
            setTracking(true);
            setMessage("Shift location is active. Keep the SupplyOS notification visible; you can end sharing at any time.");
          } catch (e) {
            await supabase.rpc("stop_employee_location_shift", { p_session_id: result.session_id, p_reason: "location_permission_or_start_failed" });
            await AsyncStorage.removeItem(SHIFT_SESSION_KEY);
            setMessage(e instanceof Error ? e.message : "Could not start background location.");
            await refresh();
          }
          setLoading(false);
        })(); } },
      ],
    );
  }

  async function resumeShift() {
    if (!activeShift) return;
    setLoading(true); setMessage("Resuming location updates…");
    try {
      await beginNativeLocationUpdates("shift");
      setTracking(true);
      setMessage("Location updates resumed for your active shift.");
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Could not resume location updates.");
    }
    setLoading(false);
  }

  async function endShift() {
    if (!activeShift) return;
    Alert.alert("End work shift?", "This stops location sharing and closes your active SupplyOS shift-location session.", [
      { text: "Keep sharing", style: "cancel" },
      { text: "End shift", style: "destructive", onPress: () => { void (async () => {
        setLoading(true);
        await stopNativeLocationUpdates();
        const { error } = await supabase.rpc("stop_employee_location_shift", {
          p_session_id: activeShift.session_id,
          p_reason: "employee_stopped",
        });
        if (error) { setMessage(error.message); setLoading(false); return; }
        await AsyncStorage.removeItem(SHIFT_SESSION_KEY);
        setActiveShift(null); setTracking(false);
        setMessage("Shift ended. Your location is no longer being shared.");
        setLoading(false);
      })(); } },
    ]);
  }

  async function signOut() {
    if (activeShift) {
      setMessage("End your active shift before signing out so location sharing can be stopped correctly.");
      return;
    }
    await supabase.auth.signOut();
    setSignedIn(false);
    setMessage("Signed out.");
  }

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar barStyle="dark-content" />
      <ScrollView contentContainerStyle={styles.content}>
        <View style={styles.brand}><View style={styles.brandMark}><Text style={styles.brandMarkText}>S</Text></View><View><Text style={styles.brandName}>SupplyOS Team</Text><Text style={styles.brandCaption}>WORK SHIFT & LOCATION</Text></View></View>
        <View style={styles.hero}><Text style={styles.eyebrow}>TEAM WORKSPACE</Text><Text style={styles.title}>Your shift,{"\n"}your control.</Text><Text style={styles.subtitle}>Start location sharing only when your work shift begins. Stop it whenever your shift ends.</Text></View>
        {!signedIn ? (
          <View style={styles.panel}>
            <Text style={styles.panelTitle}>Sign in</Text>
            <TextInput style={styles.input} autoCapitalize="none" keyboardType="email-address" placeholder="Email address" value={email} onChangeText={setEmail}/>
            <TextInput style={styles.input} secureTextEntry placeholder="Password" value={password} onChangeText={setPassword}/>
            <Pressable style={[styles.button, loading && styles.disabled]} onPress={signIn} disabled={loading}><Text style={styles.buttonText}>{loading ? "Please wait…" : "Sign in"}</Text></Pressable>
          </View>
        ) : (
          <View style={styles.panel}>
            <Text style={styles.panelTitle}>Work-shift location</Text>
            {activeShift ? (
              <>
                <View style={styles.statusRow}><View style={[styles.statusDot, tracking ? styles.dotLive : styles.dotPaused]}/><Text style={styles.statusText}>{tracking ? "Location updates active" : "Shift active · resume updates"}</Text></View>
                <Text style={styles.detail}>Shift started: {new Date(activeShift.started_at).toLocaleString()}</Text>
                {!tracking && <Pressable style={styles.button} onPress={resumeShift} disabled={loading}><Text style={styles.buttonText}>Resume location updates</Text></Pressable>}
                <Pressable style={[styles.button, styles.stopButton]} onPress={endShift} disabled={loading}><Text style={styles.buttonText}>{loading ? "Please wait…" : "End shift & stop sharing"}</Text></Pressable>
              </>
            ) : (
              <>
                <Text style={styles.detail}>No active location-sharing shift. Your location is not being shared by this feature.</Text>
                <Pressable style={styles.button} onPress={startShift} disabled={loading}><Text style={styles.buttonText}>{loading ? "Please wait…" : "Agree & start shift location"}</Text></Pressable>
              </>
            )}
            <Pressable style={styles.signOut} onPress={signOut}><Text style={styles.signOutText}>Sign out</Text></Pressable>
          </View>
        )}
        <Text style={styles.message}>{message}</Text>
        <Text style={styles.privacy}>Location sharing requires your explicit consent and Android location permission. Updates are sent while a shift session is active. Background reliability depends on device settings, battery controls and network coverage.</Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root:{flex:1,backgroundColor:"#F5F7FB"},
  content:{padding:24,paddingTop:36,paddingBottom:48},
  brand:{flexDirection:"row",alignItems:"center",gap:12,marginBottom:34},
  brandMark:{width:42,height:42,borderRadius:13,backgroundColor:"#10233F",alignItems:"center",justifyContent:"center"},
  brandMarkText:{color:"#fff",fontSize:22,fontWeight:"800"},
  brandName:{fontSize:17,fontWeight:"800",color:"#14243A"},
  brandCaption:{fontSize:9,fontWeight:"700",letterSpacing:1.5,color:"#7B8798",marginTop:3},
  hero:{marginBottom:26},
  eyebrow:{fontSize:10,fontWeight:"800",letterSpacing:1.6,color:"#4776B8",marginBottom:12},
  title:{fontSize:38,lineHeight:43,fontWeight:"800",color:"#14243A"},
  subtitle:{fontSize:15,lineHeight:23,color:"#65748A",marginTop:12,maxWidth:330},
  panel:{backgroundColor:"#fff",borderRadius:20,padding:20,borderWidth:1,borderColor:"#E4EAF2",gap:12},
  panelTitle:{fontSize:18,fontWeight:"800",color:"#14243A",marginBottom:4},
  input:{height:50,borderWidth:1,borderColor:"#DCE3ED",borderRadius:12,paddingHorizontal:14,fontSize:15,color:"#14243A"},
  button:{height:52,backgroundColor:"#2459A6",borderRadius:13,alignItems:"center",justifyContent:"center",marginTop:6},
  buttonText:{color:"#fff",fontSize:15,fontWeight:"800"},
  disabled:{opacity:.55},
  statusRow:{flexDirection:"row",alignItems:"center",gap:9},
  statusDot:{width:9,height:9,borderRadius:5},
  dotLive:{backgroundColor:"#1C9B68"},
  dotPaused:{backgroundColor:"#D18B27"},
  statusText:{fontSize:14,fontWeight:"700",color:"#1A2B42"},
  detail:{fontSize:14,lineHeight:21,color:"#65748A"},
  stopButton:{backgroundColor:"#A43B3B"},
  signOut:{alignItems:"center",padding:10,marginTop:4},
  signOutText:{color:"#66758A",fontWeight:"700"},
  message:{fontSize:13,lineHeight:20,color:"#365273",marginTop:16},
  privacy:{fontSize:11,lineHeight:18,color:"#8994A4",marginTop:22}
});
