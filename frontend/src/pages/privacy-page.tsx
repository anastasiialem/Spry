import { SiteHeader } from "@/components/site-header";

/** /privacy/ - linked from the Google OAuth consent screen. */
export function PrivacyPage() {
  return (
    <div className="min-h-svh">
      <SiteHeader page="Privacy" />
      <main className="mx-auto grid max-w-2xl gap-4 px-6 py-16 text-sm leading-relaxed">
        <h1 className="text-3xl font-bold tracking-tight text-house">
          Privacy policy
        </h1>
        <p className="text-muted-foreground">
          Spry is a university course project. This page says what it keeps
          about you.
        </p>
        <h2 className="mt-4 text-lg font-semibold">What we store</h2>
        <ul className="list-disc space-y-1 pl-5">
          <li>
            Your email address, and your name if Google provides it - kept by
            Amazon Cognito so that you can sign in.
          </li>
          <li>
            If you sign in with Google, we receive only your email, name and a
            Google account id (scopes <code>openid</code>, <code>email</code>,{" "}
            <code>profile</code>). We never see your Google password and get no
            access to Gmail, Drive or anything else.
          </li>
          <li>Meetings and files you add to the app.</li>
        </ul>
        <h2 className="mt-4 text-lg font-semibold">What we do not do</h2>
        <p>
          We do not sell or share your data, show ads, or use it for anything
          other than running this app. Data is stored on AWS in the United
          States (us-east-1).
        </p>
        <h2 className="mt-4 text-lg font-semibold">Deleting your data</h2>
        <p>
          The whole project, including every account, is deleted when the course
          ends. To have your account removed earlier, write to the address shown
          on the Google consent screen.
        </p>
      </main>
    </div>
  );
}
