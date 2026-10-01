import { useQuery } from "@tanstack/react-query";

import { Skeleton } from "@/components/ui/skeleton";
import { api } from "@/lib/api";
import { cn } from "@/lib/utils";
import { weekOverWeek } from "@/lib/week-stats";

type CalloutProps = {
  icon: string;
  label: string;
  value: number;
  previous: number;
  decimals?: number;
  unit?: string;
  tint: string;
};

function Delta({
  value,
  previous,
  decimals,
}: Pick<CalloutProps, "value" | "previous" | "decimals">) {
  const round = (n: number) => Number(n.toFixed(decimals ?? 0));
  const diff = round(value) - round(previous);
  if (diff === 0) {
    return <span className="text-muted-foreground">same as last week</span>;
  }
  return (
    <span className={cn(diff > 0 ? "text-up" : "text-down", "font-medium")}>
      {diff > 0 ? "▲ +" : "▼ "}
      {diff.toFixed(decimals ?? 0)}
      <span className="font-normal text-muted-foreground"> vs last week</span>
    </span>
  );
}

function Callout({
  icon,
  label,
  value,
  previous,
  decimals,
  unit,
  tint,
}: CalloutProps) {
  return (
    <div className={cn("flex gap-3 rounded-md px-4 py-3.5", tint)}>
      <span aria-hidden className="text-xl leading-6">
        {icon}
      </span>
      <div className="grid gap-0.5">
        <span className="text-xs font-medium text-muted-foreground">
          {label}
        </span>
        <span className="text-2xl font-semibold tracking-tight text-house tabular-nums">
          {value.toFixed(decimals ?? 0)}
          {unit && <span className="ml-1 text-base font-medium">{unit}</span>}
        </span>
        <span className="text-xs tabular-nums">
          <Delta value={value} previous={previous} decimals={decimals} />
        </span>
      </div>
    </div>
  );
}

export function MeetingStats() {
  const { data } = useQuery({
    queryKey: ["meetings"],
    queryFn: api.listMeetings,
  });

  if (!data) {
    return (
      <div className="grid gap-3 sm:grid-cols-3">
        {[0, 1, 2].map((i) => (
          <Skeleton key={i} className="h-[92px] rounded-md" />
        ))}
      </div>
    );
  }

  const { current, previous } = weekOverWeek(data);
  return (
    <section aria-label="This week" className="grid gap-3 sm:grid-cols-3">
      <Callout
        icon="📅"
        label="Meetings this week"
        value={current.count}
        previous={previous.count}
        tint="bg-tint-green"
      />
      <Callout
        icon="⏱️"
        label="Hours in meetings"
        value={current.hours}
        previous={previous.hours}
        decimals={1}
        unit="h"
        tint="bg-tint-gold"
      />
      <Callout
        icon="👥"
        label="Average attendees"
        value={current.avgAttendees}
        previous={previous.avgAttendees}
        decimals={1}
        tint="bg-tint-sand"
      />
    </section>
  );
}
