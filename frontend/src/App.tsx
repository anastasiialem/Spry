import { MeetingForm } from "@/components/meeting-form";
import { MeetingList } from "@/components/meeting-list";

export default function App() {
  return (
    <div className="min-h-svh">
      <header className="border-b bg-card">
        <div className="mx-auto flex h-14 max-w-3xl items-center gap-2 px-6">
          <span className="grid size-7 place-items-center rounded-md bg-primary text-sm font-bold text-primary-foreground">
            S
          </span>
          <span className="font-semibold tracking-tight">Spry</span>
        </div>
      </header>

      <main className="mx-auto grid max-w-3xl gap-8 px-6 py-10">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Meetings</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Everything on the calendar, soonest first.
          </p>
        </div>
        <MeetingForm />
        <section className="grid gap-3">
          <h2 className="text-sm font-medium text-muted-foreground">
            Upcoming
          </h2>
          <MeetingList />
        </section>
      </main>
    </div>
  );
}
