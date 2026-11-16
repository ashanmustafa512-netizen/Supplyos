import { redirect } from "next/navigation";
export default function RetiredDispatchLayout({ children }: Readonly<{children: React.ReactNode}>) {
  void children;
  redirect("/dashboard");
}
