"use client"

import { type ReactNode, type ButtonHTMLAttributes, forwardRef } from "react"
import { Loader2 } from "lucide-react"

export function Card({
  children,
  className = "",
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <div
      className={`rounded-[var(--radius)] border border-border bg-card p-5 sm:p-6 ${className}`}
    >
      {children}
    </div>
  )
}

export function CardHeader({
  icon,
  title,
  subtitle,
  right,
}: {
  icon?: ReactNode
  title: string
  subtitle?: string
  right?: ReactNode
}) {
  return (
    <div className="mb-5 flex items-start justify-between gap-4">
      <div className="flex items-start gap-3">
        {icon ? (
          <div className="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-lg border border-border bg-card-elevated text-primary">
            {icon}
          </div>
        ) : null}
        <div>
          <h2 className="text-[15px] font-semibold leading-tight text-foreground">{title}</h2>
          {subtitle ? (
            <p className="mt-1 text-[13px] leading-relaxed text-muted">{subtitle}</p>
          ) : null}
        </div>
      </div>
      {right}
    </div>
  )
}

export function Stat({
  label,
  value,
  tone = "default",
  mono = true,
}: {
  label: string
  value: ReactNode
  tone?: "default" | "positive" | "negative" | "warning" | "primary"
  mono?: boolean
}) {
  const toneClass =
    tone === "positive"
      ? "text-positive"
      : tone === "negative"
        ? "text-negative"
        : tone === "warning"
          ? "text-warning"
          : tone === "primary"
            ? "text-primary"
            : "text-foreground"
  return (
    <div className="rounded-xl border border-border bg-input px-4 py-3">
      <div className="text-[10px] font-medium uppercase tracking-[0.08em] text-muted">
        {label}
      </div>
      <div className={`mt-1.5 text-lg font-semibold ${mono ? "font-mono" : ""} ${toneClass}`}>
        {value}
      </div>
    </div>
  )
}

type BtnProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "danger"
  loading?: boolean
  fullWidth?: boolean
}

export const Button = forwardRef<HTMLButtonElement, BtnProps>(function Button(
  { variant = "primary", loading, fullWidth, className = "", children, disabled, ...rest },
  ref,
) {
  const base =
    "inline-flex items-center justify-center gap-2 rounded-lg px-4 py-2.5 text-sm font-semibold transition-colors disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
  const variants = {
    primary: "bg-primary text-primary-foreground hover:bg-primary/90",
    secondary: "border border-border bg-card-elevated text-foreground hover:bg-border/60",
    danger: "bg-negative text-white hover:bg-negative/90",
  }
  return (
    <button
      ref={ref}
      disabled={disabled || loading}
      className={`${base} ${variants[variant]} ${fullWidth ? "w-full" : ""} ${className}`}
      {...rest}
    >
      {loading ? <Loader2 className="size-4 animate-spin" aria-hidden /> : null}
      {children}
    </button>
  )
})

export function Field({
  value,
  onChange,
  placeholder,
  suffix,
  onMax,
  disabled,
  type = "number",
}: {
  value: string
  onChange: (v: string) => void
  placeholder?: string
  suffix?: string
  onMax?: () => void
  disabled?: boolean
  type?: string
}) {
  return (
    <div className="flex flex-1 items-center gap-2 rounded-lg border border-border bg-input px-3 focus-within:border-primary/60">
      <input
        type={type}
        inputMode="decimal"
        value={value}
        disabled={disabled}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="min-w-0 flex-1 bg-transparent py-2.5 font-mono text-sm text-foreground outline-none placeholder:text-muted/70 disabled:opacity-50"
      />
      {suffix ? <span className="shrink-0 text-xs font-medium text-muted">{suffix}</span> : null}
      {onMax ? (
        <button
          type="button"
          onClick={onMax}
          className="shrink-0 rounded-md border border-border px-2 py-1 text-[11px] font-semibold text-primary hover:bg-primary-dim/40"
        >
          MAX
        </button>
      ) : null}
    </div>
  )
}
