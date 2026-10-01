import type { Meeting } from "@/lib/api";

const DAY = 24 * 60 * 60 * 1000;

/** Monday 00:00 of the week containing `date`, in the browser's time zone. */
export function startOfWeek(date: Date): Date {
  const start = new Date(date);
  start.setHours(0, 0, 0, 0);
  const daysSinceMonday = (start.getDay() + 6) % 7;
  start.setDate(start.getDate() - daysSinceMonday);
  return start;
}

export type WeekMetrics = {
  count: number;
  hours: number;
  avgAttendees: number;
};

function metricsFor(meetings: Meeting[]): WeekMetrics {
  const count = meetings.length;
  const hours = meetings.reduce(
    (sum, m) =>
      sum + (Date.parse(m.ends_at) - Date.parse(m.starts_at)) / 3_600_000,
    0,
  );
  const attendees = meetings.reduce((sum, m) => sum + m.attendee_count, 0);
  return { count, hours, avgAttendees: count ? attendees / count : 0 };
}

/** This week's and last week's metrics; a meeting belongs to the week it starts in. */
export function weekOverWeek(
  meetings: Meeting[],
  now: Date = new Date(),
): { current: WeekMetrics; previous: WeekMetrics } {
  const thisWeek = startOfWeek(now).getTime();
  const lastWeek = thisWeek - 7 * DAY;
  const nextWeek = thisWeek + 7 * DAY;
  const inRange = (from: number, to: number) =>
    meetings.filter((m) => {
      const t = Date.parse(m.starts_at);
      return t >= from && t < to;
    });
  return {
    current: metricsFor(inRange(thisWeek, nextWeek)),
    previous: metricsFor(inRange(lastWeek, thisWeek)),
  };
}
