import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator, Alert, AppState, Pressable, SafeAreaView, ScrollView,
  StatusBar, StyleSheet, Text, TextInput, View,
} from "react-native";
import { supabase } from "./src/supabase";
import {
  beginNativeLocationUpdates, stopNativeLocationUpdates, AsyncStorage, SHIFT_SESSION_KEY,
} from "./src/trackingTask";

type ActiveShift = { session_id: string; employee_name: string; started_at?: string };
type Shop = { id: string; customer_code: string; name: string; city: string | null; region: string | null };
type Product = { id: string; sku: string; name: string; unit: string; unit_price: number | string; stock_on_hand: number | string; stock_reserved: number | string };
type MyBooking = { id: string; booking_no: string; status: string; booking_date: string; total_amount: number | string; customers?: { name: string } | { name: string }[] | null };

const SHIFT_CONSENT_VERSION = "supplyos-work-shift-location-consent-v2";

export default function App() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [signedIn, setSignedIn] = useState(false);
  const [employeeName, setEmployeeName] = useState("Employee");
  const [loading, setLoading] = useState(false);
  const [trackingReady, setTrackingReady] = useState(false);
  const [activeShift, setActiveShift] = useState<ActiveShift | null>(null);
  const [tab, setTab] = useState<"new" | "mine">("new");
  const [shops, setShops] = useState<Shop[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [bookings, setBookings] = useState<MyBooking[]>([]);
  const [shopSearch, setShopSearch] = useState("");
  const [productSearch, setProductSearch] = useState("");
  const [selectedShop, setSelectedShop] = useState<Shop | null>(null);
  const [selectedProduct, setSelectedProduct] = useState<Product | null>(null);
  const [quantity, setQuantity] = useState("1");
  const [notes, setNotes] = useState("");
  const [message, setMessage] = useState("Sign in with your SupplyOS employee account.");

  const loadWorkspaceData = useCallback(async () => {
    const { data: authData } = await supabase.auth.getUser();
    const user = authData.user;
    if (!user) return;

    const { data: membership, error: membershipError } = await supabase
      .from("memberships")
      .select("organization_id,role")
      .eq("user_id", user.id)
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (membershipError || !membership) {
      setMessage(membershipError?.message ?? "Your account is not connected to a factory workspace.");
      return;
    }
    if (membership.role !== "staff") {
      setMessage("This is the Employee app. Please sign in with an employee account; managers should use the Manager app.");
      await supabase.auth.signOut();
      setSignedIn(false);
      return;
    }

    const [shopResult, productResult, bookingResult, profileResult] = await Promise.all([
      supabase.from("customers").select("id,customer_code,name,city,region")
        .eq("organization_id", membership.organization_id).eq("status", "active").order("name").limit(1000),
      supabase.from("products").select("id,sku,name,unit,unit_price,stock_on_hand,stock_reserved")
        .eq("organization_id", membership.organization_id).eq("is_active", true).order("name").limit(1000),
      supabase.from("bookings").select("id,booking_no,status,booking_date,total_amount,customers(name)")
        .eq("organization_id", membership.organization_id).order("created_at", { ascending: false }).limit(30),
      supabase.from("profiles").select("full_name").eq("id", user.id).maybeSingle(),
    ]);
    if (shopResult.error || productResult.error || bookingResult.error) {
      setMessage(shopResult.error?.message ?? productResult.error?.message ?? bookingResult.error?.message ?? "Workspace data could not be loaded.");
    }
    setShops((shopResult.data ?? []) as Shop[]);
    setProducts((productResult.data ?? []) as Product[]);
    setBookings((bookingResult.data ?? []) as unknown as MyBooking[]);
    setEmployeeName(profileResult.data?.full_name || user.email?.split("@")[0] || "Employee");
  }, []);

  const refresh = useCallback(async () => {
    const { data: sessionData } = await supabase.auth.getSession();
    const session = sessionData.session;
    setSignedIn(!!session);
    if (!session) {
      setActiveShift(null);
      setTrackingReady(false);
      return;
    }

    const { data: shiftRows, error } = await supabase
      .from("employee_location_sessions")
      .select("id,employee_name,started_at")
      .eq("user_id", session.user.id)
      .is("ended_at", null)
      .order("started_at", { ascending: false })
      .limit(1);
    if (error) setMessage(error.message);
    const row = shiftRows?.[0];
    if (row) {
      await AsyncStorage.setItem(SHIFT_SESSION_KEY, row.id);
      setActiveShift({ session_id: row.id, employee_name: row.employee_name, started_at: row.started_at });
      try {
        await beginNativeLocationUpdates();
        setTrackingReady(true);
        setMessage("Your work-shift location is active.");
      } catch (e) {
        setTrackingReady(false);
        setMessage(e instanceof Error ? e.message : "Location permission is required to continue.");
      }
    } else {
      await AsyncStorage.removeItem(SHIFT_SESSION_KEY);
      setActiveShift(null);
      setTrackingReady(false);
    }
    await loadWorkspaceData();
  }, [loadWorkspaceData]);

  useEffect(() => {
    void refresh();
    const subscription = AppState.addEventListener("change", state => {
      if (state === "active") void refresh();
    });
    const interval = setInterval(() => {
      if (activeShift) void refresh();
    }, 30000);
    return () => {
      subscription.remove();
      clearInterval(interval);
    };
  }, [activeShift, refresh]);

  async function signIn() {
    setLoading(true);
    setMessage("Signing in…");
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) {
      setLoading(false);
      setMessage(error.message);
      return;
    }
    await refresh();
    setLoading(false);
  }

  async function startShift() {
    Alert.alert(
      "Enable work-shift location?",
      "While your work shift is active, SupplyOS shares this phone's location with the factory owner. This helps the owner see the live location of employees during working hours. Location sharing stops when you end your shift. Android will show a persistent location notification.",
      [
        { text: "Not now", style: "cancel" },
        { text: "Agree & start shift", onPress: () => { void (async () => {
          setLoading(true);
          setMessage("Checking location permissions…");
          let createdSessionId: string | null = null;
          try {
            await beginNativeLocationUpdates();
            const { data, error } = await supabase.rpc("start_employee_location_shift", {
              p_consent_version: SHIFT_CONSENT_VERSION,
            });
            if (error) throw error;
            const result = data as { session_id: string; employee_name: string; started_at?: string };
            createdSessionId = result.session_id;
            await AsyncStorage.setItem(SHIFT_SESSION_KEY, result.session_id);
            setActiveShift({ session_id: result.session_id, employee_name: result.employee_name, started_at: result.started_at });
            setTrackingReady(true);
            setMessage("Work-shift location is active. You can now create shop bookings.");
          } catch (error) {
            await stopNativeLocationUpdates();
            if (createdSessionId) {
              await supabase.rpc("stop_employee_location_shift", {
                p_session_id: createdSessionId,
                p_reason: "location_permission_or_start_failed",
              });
            }
            await AsyncStorage.removeItem(SHIFT_SESSION_KEY);
            setActiveShift(null);
            setTrackingReady(false);
            setMessage(error instanceof Error ? error.message : "Could not start the location session.");
          } finally {
            setLoading(false);
          }
        })(); } },
      ],
    );
  }

  async function endShift() {
    if (!activeShift) return;
    Alert.alert("End work shift?", "This stops location sharing and closes your active work session.", [
      { text: "Keep shift active", style: "cancel" },
      { text: "End shift", style: "destructive", onPress: () => { void (async () => {
        setLoading(true);
        await stopNativeLocationUpdates();
        const { error } = await supabase.rpc("stop_employee_location_shift", {
          p_session_id: activeShift.session_id,
          p_reason: "employee_stopped",
        });
        await AsyncStorage.removeItem(SHIFT_SESSION_KEY);
        setActiveShift(null);
        setTrackingReady(false);
        setLoading(false);
        setMessage(error ? `Phone tracking stopped, but the server could not close the shift: ${error.message}` : "Shift ended. No new location updates will be sent.");
      })(); } },
    ]);
  }

  async function enableLocationAgain() {
    setLoading(true);
    try {
      await beginNativeLocationUpdates();
      setTrackingReady(true);
      setMessage("Location permission is active again.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Location access is still unavailable.");
    } finally {
      setLoading(false);
    }
  }

  async function createBooking() {
    const qty = Number(quantity);
    if (!selectedShop || !selectedProduct || !Number.isFinite(qty) || qty <= 0) {
      setMessage("Choose a shop, a product and a quantity greater than zero.");
      return;
    }
    setLoading(true);
    setMessage("Submitting booking…");
    const { data, error } = await supabase.rpc("create_booking", {
      p_customer_id: selectedShop.id,
      p_product_id: selectedProduct.id,
      p_quantity: qty,
      p_notes: notes.trim(),
    });
    if (error) {
      setMessage(error.message);
    } else {
      setMessage(`Booking created successfully: ${String(data)}. It is now waiting for owner approval.`);
      setSelectedShop(null);
      setSelectedProduct(null);
      setShopSearch("");
      setProductSearch("");
      setQuantity("1");
      setNotes("");
      await loadWorkspaceData();
      setTab("mine");
    }
    setLoading(false);
  }

  async function signOut() {
    if (activeShift) {
      await stopNativeLocationUpdates();
      await supabase.rpc("stop_employee_location_shift", {
        p_session_id: activeShift.session_id,
        p_reason: "employee_signed_out",
      });
      await AsyncStorage.removeItem(SHIFT_SESSION_KEY);
    }
    await supabase.auth.signOut();
    setSignedIn(false);
    setActiveShift(null);
    setTrackingReady(false);
    setBookings([]);
    setShops([]);
    setProducts([]);
  }

  const filteredShops = useMemo(() => {
    const q = shopSearch.trim().toLowerCase();
    return shops.filter(shop => !q || `${shop.name} ${shop.customer_code} ${shop.city ?? ""} ${shop.region ?? ""}`.toLowerCase().includes(q)).slice(0, 8);
  }, [shops, shopSearch]);
  const filteredProducts = useMemo(() => {
    const q = productSearch.trim().toLowerCase();
    return products.filter(product => !q || `${product.name} ${product.sku}`.toLowerCase().includes(q)).slice(0, 8);
  }, [products, productSearch]);

  if (!signedIn) {
    return <SafeAreaView style={styles.safe}><StatusBar barStyle="light-content" backgroundColor="#0b1220"/>
      <ScrollView contentContainerStyle={styles.container}>
        <Brand/>
        <Card><Text style={styles.heading}>Employee sign in</Text>
          <Field value={email} onChangeText={setEmail} placeholder="Email" keyboardType="email-address"/>
          <Field value={password} onChangeText={setPassword} placeholder="Password" secureTextEntry/>
          <ActionButton title="Sign in" onPress={() => void signIn()} disabled={loading || !email.trim() || !password}/>
          <Text style={styles.muted}>{message}</Text>
        </Card>
      </ScrollView>
    </SafeAreaView>;
  }

  return <SafeAreaView style={styles.safe}><StatusBar barStyle="light-content" backgroundColor="#0b1220"/>
    <ScrollView contentContainerStyle={styles.container}>
      <Brand subtitle="Shop orders and work-shift location"/>
      {activeShift ? <Card active>
        <Text style={styles.pill}>{trackingReady ? "LOCATION SHARING ACTIVE" : "LOCATION PERMISSION REQUIRED"}</Text>
        <Text style={styles.heading}>Hello, {activeShift.employee_name}</Text>
        <Text style={styles.body}>{trackingReady
          ? "Your live work-shift location is shared with the factory owner. It stops when you end your shift."
          : "Location access is unavailable. Re-enable it to continue using the employee app and sharing your work-shift location."}</Text>
        {!trackingReady
          ? <ActionButton title="Enable location to continue" onPress={() => void enableLocationAgain()} disabled={loading}/>
          : <ActionButton title="End shift & stop sharing" onPress={() => void endShift()} danger disabled={loading}/>}
      </Card> : <Card>
        <Text style={styles.heading}>Start your workday</Text>
        <Text style={styles.body}>Enable location before taking shop orders. Location is shared only after you agree and while this work shift is active.</Text>
        <ActionButton title="Agree & enable location" onPress={() => void startShift()} disabled={loading}/>
        <Text style={styles.muted}>{message}</Text>
      </Card>}

      {activeShift && trackingReady ? <>
        <View style={styles.tabs}>
          <Tab title="New booking" active={tab === "new"} onPress={() => setTab("new")}/>
          <Tab title="My bookings" active={tab === "mine"} onPress={() => { setTab("mine"); void loadWorkspaceData(); }}/>
        </View>
        {tab === "new" ? <Card>
          <Text style={styles.heading}>Create a shop booking</Text>
          <Text style={styles.fieldLabel}>Choose shop</Text>
          {selectedShop ? <Selected label={selectedShop.name} detail={`${selectedShop.customer_code} · ${selectedShop.city ?? "Location not set"}`} onClear={() => setSelectedShop(null)}/> : <>
            <Field value={shopSearch} onChangeText={setShopSearch} placeholder="Search shop name or code"/>
            {filteredShops.map(shop => <Choice key={shop.id} title={shop.name} detail={`${shop.customer_code} · ${shop.city ?? "No city"}`} onPress={() => { setSelectedShop(shop); setShopSearch(""); }}/>)}
            {!filteredShops.length && <Text style={styles.muted}>No matching active shop. Ask the owner or manager to add this shop to SupplyOS.</Text>}
          </>}
          <Text style={styles.fieldLabel}>Choose product</Text>
          {selectedProduct ? <Selected label={selectedProduct.name} detail={`${selectedProduct.sku} · Available ${Number(selectedProduct.stock_on_hand) - Number(selectedProduct.stock_reserved)} ${selectedProduct.unit}`} onClear={() => setSelectedProduct(null)}/> : <>
            <Field value={productSearch} onChangeText={setProductSearch} placeholder="Search product name or SKU"/>
            {filteredProducts.map(product => <Choice key={product.id} title={product.name} detail={`${product.sku} · ${product.unit} · Available ${Number(product.stock_on_hand) - Number(product.stock_reserved)}`} onPress={() => { setSelectedProduct(product); setProductSearch(""); }}/>)}
            {!filteredProducts.length && <Text style={styles.muted}>No matching active product.</Text>}
          </>}
          <Text style={styles.fieldLabel}>Quantity</Text>
          <Field value={quantity} onChangeText={setQuantity} keyboardType="decimal-pad" placeholder="Enter quantity"/>
          <Text style={styles.fieldLabel}>Notes (optional)</Text>
          <Field value={notes} onChangeText={setNotes} placeholder="Special instructions or shop reference"/>
          <ActionButton title="Submit booking for approval" onPress={() => void createBooking()} disabled={loading || !selectedShop || !selectedProduct || !(Number(quantity) > 0)}/>
          <Text style={styles.muted}>Owner approval checks shop credit and available stock before an order is approved.</Text>
        </Card> : <Card>
          <Text style={styles.heading}>My bookings</Text>
          <Text style={styles.muted}>Only bookings submitted by your employee account appear here.</Text>
          {bookings.map(booking => {
            const customer = Array.isArray(booking.customers) ? booking.customers[0] : booking.customers;
            return <View key={booking.id} style={styles.bookingRow}>
              <View style={styles.bookingCopy}><Text style={styles.bookingNo}>{booking.booking_no}</Text><Text style={styles.muted}>{customer?.name ?? "Shop"} · {booking.booking_date}</Text></View>
              <View style={styles.bookingStatus}><Text style={styles.statusText}>{booking.status.replaceAll("_", " ")}</Text><Text style={styles.muted}>{Number(booking.total_amount).toLocaleString()}</Text></View>
            </View>;
          })}
          {!bookings.length && <Text style={styles.muted}>You have not submitted any bookings yet.</Text>}
        </Card>}
        <ActionButton title="Refresh my bookings" secondary onPress={() => void loadWorkspaceData()} disabled={loading}/>
      </> : null}

      <ActionButton title="Sign out" secondary onPress={() => void signOut()} disabled={loading}/>
      {loading && <ActivityIndicator color="#93c5fd"/>}
      <Text style={styles.privacy}>Location is collected only during an active work shift that you explicitly start. Ending the shift stops the background GPS task and closes the server session.</Text>
    </ScrollView>
  </SafeAreaView>;
}

function Brand({ subtitle = "SUPPLYOS EMPLOYEE APP" }: { subtitle?: string }) {
  return <View style={styles.brand}><Text style={styles.kicker}>SUPPLYOS · EMPLOYEE</Text><Text style={styles.title}>Your field work,<Text style={styles.titleAccent}> organized.</Text></Text><Text style={styles.subtitle}>{subtitle}</Text></View>;
}
function Card({ children, active = false }: { children: React.ReactNode; active?: boolean }) {
  return <View style={[styles.card, active && styles.activeCard]}>{children}</View>;
}
function Field({ value, onChangeText, placeholder, secureTextEntry, keyboardType }: {
  value: string; onChangeText: (value: string) => void; placeholder: string;
  secureTextEntry?: boolean; keyboardType?: "email-address" | "decimal-pad";
}) {
  return <TextInput style={styles.input} value={value} onChangeText={onChangeText}
    placeholder={placeholder} placeholderTextColor="#8792a8" secureTextEntry={secureTextEntry}
    keyboardType={keyboardType} autoCapitalize={keyboardType === "email-address" ? "none" : "sentences"}/>;
}
function ActionButton({ title, onPress, disabled, secondary, danger }: {
  title: string; onPress: () => void; disabled?: boolean; secondary?: boolean; danger?: boolean;
}) {
  return <Pressable onPress={onPress} disabled={disabled}
    style={[styles.button, secondary && styles.secondaryButton, danger && styles.dangerButton, disabled && styles.disabled]}>
    <Text style={styles.buttonText}>{title}</Text>
  </Pressable>;
}
function Choice({ title, detail, onPress }: { title: string; detail: string; onPress: () => void }) {
  return <Pressable onPress={onPress} style={styles.choice}><Text style={styles.choiceTitle}>{title}</Text><Text style={styles.muted}>{detail}</Text></Pressable>;
}
function Selected({ label, detail, onClear }: { label: string; detail: string; onClear: () => void }) {
  return <View style={styles.selected}><View style={{flex:1}}><Text style={styles.choiceTitle}>{label}</Text><Text style={styles.muted}>{detail}</Text></View><Pressable onPress={onClear}><Text style={styles.clear}>Change</Text></Pressable></View>;
}
function Tab({ title, active, onPress }: { title: string; active: boolean; onPress: () => void }) {
  return <Pressable onPress={onPress} style={[styles.tab, active && styles.activeTab]}><Text style={[styles.tabText, active && styles.activeTabText]}>{title}</Text></Pressable>;
}
const styles = StyleSheet.create({
  safe:{flex:1,backgroundColor:"#0b1220"},container:{padding:20,gap:14,paddingBottom:40},
  brand:{paddingVertical:12},kicker:{color:"#60a5fa",fontWeight:"800",letterSpacing:2,fontSize:11},
  title:{color:"#f8fafc",fontSize:30,fontWeight:"800",marginTop:8},titleAccent:{color:"#93c5fd"},
  subtitle:{color:"#aab6c9",fontSize:14,lineHeight:21,marginTop:8},
  card:{backgroundColor:"#141e30",borderColor:"#2b3950",borderWidth:1,borderRadius:16,padding:18,gap:12},
  activeCard:{borderColor:"#2d9875"},heading:{color:"#f8fafc",fontSize:19,fontWeight:"800"},
  body:{color:"#e2e8f0",fontSize:14,lineHeight:21},muted:{color:"#aab6c9",fontSize:12,lineHeight:18},
  input:{backgroundColor:"#0b1220",borderColor:"#334155",borderWidth:1,borderRadius:10,padding:13,color:"#f8fafc",marginTop:4},
  fieldLabel:{color:"#e2e8f0",fontSize:13,fontWeight:"700",marginTop:4},
  button:{backgroundColor:"#3b82f6",padding:14,borderRadius:10,alignItems:"center",marginTop:4},
  buttonText:{color:"#fff",fontWeight:"800"},secondaryButton:{backgroundColor:"transparent",borderColor:"#41516b",borderWidth:1},
  dangerButton:{backgroundColor:"#b91c1c"},disabled:{opacity:0.45},
  pill:{color:"#6ee7b7",fontSize:11,fontWeight:"900",letterSpacing:1.2},
  tabs:{flexDirection:"row",gap:8},tab:{flex:1,padding:13,borderRadius:10,borderWidth:1,borderColor:"#334155",alignItems:"center"},
  activeTab:{backgroundColor:"#1d4ed8",borderColor:"#3b82f6"},tabText:{color:"#aab6c9",fontWeight:"700"},activeTabText:{color:"#fff"},
  choice:{padding:12,borderTopWidth:1,borderTopColor:"#2b3950",gap:3},choiceTitle:{color:"#f8fafc",fontWeight:"700",fontSize:14},
  selected:{padding:12,borderRadius:10,borderColor:"#2d9875",borderWidth:1,flexDirection:"row",alignItems:"center",gap:10},
  clear:{color:"#93c5fd",fontWeight:"800"},bookingRow:{borderTopWidth:1,borderTopColor:"#2b3950",paddingVertical:12,flexDirection:"row",alignItems:"center",gap:10},
  bookingCopy:{flex:1,gap:4},bookingNo:{color:"#f8fafc",fontWeight:"800"},bookingStatus:{alignItems:"flex-end",gap:3},
  statusText:{color:"#93c5fd",fontWeight:"700",textTransform:"capitalize"},privacy:{color:"#8190a8",fontSize:11,lineHeight:17,padding:8},
});
