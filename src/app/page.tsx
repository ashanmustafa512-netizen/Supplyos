import { redirect } from "next/navigation";
import { isSupabaseConfigured } from "@/lib/env";

export default function HomePage() {
  redirect(isSupabaseConfigured ? "/dashboard" : "/setup");
}
