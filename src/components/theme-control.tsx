"use client";

import { useEffect, useState } from "react";
import { Moon, Sun } from "lucide-react";

type Theme = "light" | "dark";

export function ThemeControl() {
  const [theme, setTheme] = useState<Theme>("light");
  useEffect(() => {
    const stored = window.localStorage.getItem("supplyos-theme");
    const initial: Theme = stored === "dark" ? "dark" : "light";
    setTheme(initial);
    document.documentElement.dataset.theme = initial;
    document.documentElement.style.colorScheme = initial;
  }, []);

  function setSelectedTheme(next: Theme) {
    setTheme(next);
    document.documentElement.dataset.theme = next;
    document.documentElement.style.colorScheme = next;
    window.localStorage.setItem("supplyos-theme", next);
  }

  return (
    <div className="theme-control" role="group" aria-label="Color theme">
      <button type="button" className={theme === "light" ? "theme-choice theme-choice-active" : "theme-choice"} aria-pressed={theme === "light"} onClick={() => setSelectedTheme("light")} title="Light theme"><Sun size={15}/><span>Light</span></button>
      <button type="button" className={theme === "dark" ? "theme-choice theme-choice-active" : "theme-choice"} aria-pressed={theme === "dark"} onClick={() => setSelectedTheme("dark")} title="Dark theme"><Moon size={15}/><span>Dark</span></button>
    </div>
  );
}
