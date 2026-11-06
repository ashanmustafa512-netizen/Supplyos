import React, { useMemo, useState } from "react";
import { ActivityIndicator, SafeAreaView, StyleSheet, Text, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import { WebView } from "react-native-webview";

const ADMIN_URL = process.env.EXPO_PUBLIC_ADMIN_URL;

export default function App() {
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);
  const source = useMemo(() => {
    if (!ADMIN_URL) return undefined;
    try {
      const url = new URL(ADMIN_URL);
      if (url.protocol !== "https:" && url.hostname !== "localhost") return undefined;
      return { uri: url.toString() };
    } catch { return undefined; }
  }, []);

  if (!source) return <SafeAreaView style={styles.center}><StatusBar style="light" /><Text style={styles.title}>SupplyOS Admin & Dispatch</Text><Text style={styles.message}>Set EXPO_PUBLIC_ADMIN_URL to your deployed HTTPS SupplyOS web app, then rebuild this APK.</Text></SafeAreaView>;

  return <SafeAreaView style={styles.root}>
    <StatusBar style="dark" />
    {loading && !failed && <View style={styles.loading}><ActivityIndicator size="large" /><Text style={styles.loadingText}>Opening SupplyOS…</Text></View>}
    {failed ? <View style={styles.center}><Text style={styles.title}>Unable to open SupplyOS</Text><Text style={styles.message}>Check the internet connection and deployed website URL, then reopen the app.</Text></View> :
      <WebView source={source} onLoadStart={() => { setLoading(true); setFailed(false); }} onLoadEnd={() => setLoading(false)} onError={() => { setLoading(false); setFailed(true); }} onHttpError={(event) => { if (event.nativeEvent.statusCode >= 500) setFailed(true); }} javaScriptEnabled domStorageEnabled sharedCookiesEnabled thirdPartyCookiesEnabled setSupportMultipleWindows={false} allowsBackForwardNavigationGestures originWhitelist={["https://*", "http://localhost/*"]} startInLoadingState style={styles.web} />}
  </SafeAreaView>;
}

const styles = StyleSheet.create({root:{flex:1,backgroundColor:"#fff"},web:{flex:1},loading:{position:"absolute",zIndex:2,top:0,left:0,right:0,bottom:0,alignItems:"center",justifyContent:"center",backgroundColor:"#fff"},loadingText:{marginTop:12,color:"#0B1220"},center:{flex:1,backgroundColor:"#0B1220",alignItems:"center",justifyContent:"center",padding:28},title:{color:"#fff",fontSize:22,fontWeight:"700",textAlign:"center",marginBottom:12},message:{color:"#D7DEEA",fontSize:15,lineHeight:22,textAlign:"center"}});
