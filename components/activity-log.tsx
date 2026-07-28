"use client"

import { useWallet } from "@/components/wallet-provider"
import { Card, CardHeader } from "@/components/ui-bits"
import { ScrollText, CheckCircle2, XCircle, Loader2, Info } from "lucide-react"

const ICONS = {
  info: <Info className="size-3.5 text-muted" aria-hidden />,
  success: <CheckCircle2 className="size-3.5 text-positive" aria-hidden />,
  error: <XCircle className="size-3.5 text-negative" aria-hidden />,
  pending: <Loader2 className="size-3.5 animate-spin text-primary" aria-hidden />,
}

export function ActivityLog() {
  const { log } = useWallet()

  return (
    <Card>
      <CardHeader
        icon={<ScrollText className="size-4" aria-hidden />}
        title="Activity"
        subtitle="Live feed of your transactions and protocol interactions."
      />
      <div className="thin-scroll max-h-72 space-y-2 overflow-y-auto pr-1">
        {log.length === 0 ? (
          <p className="py-8 text-center text-[13px] text-muted">No activity yet.</p>
        ) : (
          log.map((e) => (
            <div
              key={e.id}
              className="flex items-start gap-2.5 rounded-lg border border-border bg-input px-3 py-2"
            >
              <span className="mt-0.5">{ICONS[e.kind]}</span>
              <div className="min-w-0 flex-1">
                <p className="break-words text-[13px] leading-snug text-foreground">{e.msg}</p>
                <p className="mt-0.5 font-mono text-[10px] text-muted">{e.time}</p>
              </div>
            </div>
          ))
        )}
      </div>
    </Card>
  )
}
