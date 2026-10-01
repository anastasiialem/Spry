import { useQuery } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight, Users } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { api, type Meeting } from "@/lib/api";
import { STATUS } from "@/lib/status";
import { cn } from "@/lib/utils";
import { startOfWeek } from "@/lib/week-stats";

const weekdayFmt = new Intl.DateTimeFormat(undefined, { weekday: "narrow" });
const dayTitleFmt = new Intl.DateTimeFormat(undefined, {
  weekday: "long",
  day: "numeric",
  month: "long",
});
const monthFmt = new Intl.DateTimeFormat(undefined, {
  month: "long",
  year: "numeric",
});
const timeFmt = new Intl.DateTimeFormat(undefined, {
  hour: "2-digit",
  minute: "2-digit",
});

const addDays = (date: Date, days: number) => {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
};

const sameDay = (a: Date, b: Date) =>
  a.getFullYear() === b.getFullYear() &&
  a.getMonth() === b.getMonth() &&
  a.getDate() === b.getDate();

function AgendaItem({
  meeting,
  onOpen,
}: {
  meeting: Meeting;
  onOpen: (id: number) => void;
}) {
  const start = new Date(meeting.starts_at);
  const end = new Date(meeting.ends_at);
  const meta = STATUS[meeting.status];
  return (
    <li className="grid grid-cols-[3.25rem_1fr] gap-3">
      <div className="pt-2 text-right text-xs text-muted-foreground tabular-nums">
        {timeFmt.format(start)}
      </div>
      <button
        type="button"
        onClick={() => onOpen(meeting.id)}
        className="flex gap-2.5 rounded-md border bg-card/95 p-2.5 text-left shadow-[0_1px_2px_rgb(0_0_0/0.04)] transition-colors hover:border-primary/40"
      >
        <span
          aria-hidden
          className={cn("w-1 shrink-0 self-stretch rounded-full", meta.dot)}
        />
        <div className="grid min-w-0 gap-1">
          <p
            className={cn(
              "truncate text-sm font-medium",
              meeting.status === "done" &&
                "text-muted-foreground line-through decoration-1",
            )}
          >
            {meeting.title}
          </p>
          <p className="flex items-center gap-2 text-xs text-muted-foreground tabular-nums">
            {timeFmt.format(start)}–{timeFmt.format(end)}
            <span className="inline-flex items-center gap-1">
              <Users className="size-3" />
              {meeting.attendee_count}
            </span>
          </p>
          <span className="text-[11px] text-muted-foreground">
            {meta.label}
          </span>
        </div>
      </button>
    </li>
  );
}

export function Schedule({ onOpen }: { onOpen: (id: number) => void }) {
  const today = new Date();
  const [selected, setSelected] = useState(today);
  const weekStart = startOfWeek(selected);
  const days = Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));

  const { data, isPending } = useQuery({
    queryKey: ["meetings"],
    queryFn: api.listMeetings,
  });
  const meetings = data ?? [];
  const onDay = (day: Date) =>
    meetings.filter((m) => sameDay(new Date(m.starts_at), day));
  const agenda = onDay(selected);

  return (
    <aside
      aria-label="Schedule"
      className="relative isolate grid gap-4 overflow-hidden rounded-xl border bg-card p-4 shadow-[0_1px_2px_rgb(0_0_0/0.04)]"
    >
      {/* Tulips, kept faint under a white wash so text keeps its contrast. */}
      <img
        src="/images/tulips.jpg"
        alt=""
        aria-hidden
        className="absolute inset-0 -z-20 size-full object-cover opacity-45"
      />
      <div
        aria-hidden
        className="absolute inset-0 -z-10 bg-gradient-to-b from-card/80 via-card/70 to-card/85"
      />
      <img
        src="/images/magnolia.png"
        alt=""
        aria-hidden
        className="pointer-events-none absolute -right-6 -bottom-5 -z-10 w-28 -rotate-12 opacity-90"
      />

      <div className="flex items-center justify-between gap-2">
        <div>
          <h2 className="text-sm font-semibold text-house">Schedule</h2>
          <p className="text-xs text-muted-foreground capitalize">
            {monthFmt.format(weekStart)}
          </p>
        </div>
        <div className="flex items-center gap-1">
          <Button
            variant="ghost"
            size="icon"
            className="size-7"
            aria-label="Previous week"
            onClick={() => setSelected(addDays(selected, -7))}
          >
            <ChevronLeft />
          </Button>
          <Button
            variant="outline"
            size="sm"
            className="h-7 px-2 text-xs"
            onClick={() => setSelected(new Date())}
          >
            Today
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="size-7"
            aria-label="Next week"
            onClick={() => setSelected(addDays(selected, 7))}
          >
            <ChevronRight />
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-7 gap-1" role="group" aria-label="Week">
        {days.map((day) => {
          const isSelected = sameDay(day, selected);
          const isToday = sameDay(day, today);
          const busy = onDay(day).length > 0;
          return (
            <button
              key={day.toISOString()}
              type="button"
              aria-pressed={isSelected}
              aria-label={dayTitleFmt.format(day)}
              onClick={() => setSelected(day)}
              className={cn(
                "grid justify-items-center gap-0.5 rounded-md py-1.5 text-xs transition-colors",
                isSelected
                  ? "bg-house text-house-foreground"
                  : "hover:bg-card/80",
              )}
            >
              <span
                className={cn(
                  "text-[10px] uppercase",
                  isSelected ? "opacity-80" : "text-muted-foreground",
                )}
              >
                {weekdayFmt.format(day)}
              </span>
              <span
                className={cn(
                  "font-semibold tabular-nums",
                  isToday && !isSelected && "text-primary",
                )}
              >
                {day.getDate()}
              </span>
              <span
                aria-hidden
                className={cn(
                  "size-1 rounded-full",
                  busy
                    ? isSelected
                      ? "bg-lime"
                      : "bg-primary"
                    : "bg-transparent",
                )}
              />
            </button>
          );
        })}
      </div>

      <div className="grid gap-3">
        <h3 className="text-xs font-medium text-muted-foreground first-letter:uppercase">
          {dayTitleFmt.format(selected)}
        </h3>
        {isPending ? (
          <Skeleton className="h-16 rounded-md" />
        ) : agenda.length === 0 ? (
          <p className="rounded-md border border-dashed bg-card/60 py-6 text-center text-xs text-muted-foreground">
            Nothing scheduled
          </p>
        ) : (
          <ol className="relative grid gap-2.5 before:absolute before:top-2 before:bottom-2 before:left-[3.85rem] before:w-px before:bg-border">
            {agenda.map((m) => (
              <AgendaItem key={m.id} meeting={m} onOpen={onOpen} />
            ))}
          </ol>
        )}
      </div>
    </aside>
  );
}
