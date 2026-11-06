export function money(value: number | string | null | undefined, currency = "PKR") {
  const amount = Number(value ?? 0);
  return new Intl.NumberFormat("en-PK", {
    style: "currency",
    currency,
    maximumFractionDigits: 0,
  }).format(Number.isFinite(amount) ? amount : 0);
}

export function compactNumber(value: number | string | null | undefined) {
  return new Intl.NumberFormat("en-PK", { maximumFractionDigits: 1 }).format(Number(value ?? 0));
}

export function dateLabel(value: string) {
  const date = new Date(`${value.slice(0, 10)}T12:00:00`);
  return new Intl.DateTimeFormat("en-PK", { day: "numeric", month: "short", year: "numeric" }).format(date);
}
