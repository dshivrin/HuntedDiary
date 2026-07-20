# Create the Tom’s Diary Reply Shortcut

Create this Shortcut once on each Apple Intelligence-compatible iOS or iPadOS 26 device where you want Tom’s Diary to generate replies. After setup, you write in the diary as usual: when you stop writing, Tom’s Diary starts the Shortcut automatically and returns to the same uncleared canvas with the reply.

You do not need an OpenAI API key or a ChatGPT account. Enable the ChatGPT extension in Apple Intelligence; signing in to a free or paid ChatGPT account is optional.

## Before you begin

You need all of the following:

- iOS or iPadOS 26 or later.
- Tom’s Diary installed with Shortcut support enabled.
- An Apple Intelligence-compatible iPhone or iPad, with Apple Intelligence enabled.
- The ChatGPT extension enabled at **Settings → Apple Intelligence & Siri → ChatGPT**. Account sign-in is optional.
- The Shortcuts app.

> The iPad mini 6 is not compatible with Apple Intelligence, so it cannot use this ChatGPT Extension Model Shortcut even if it can install iPadOS 26. Use iPad mini (A17 Pro), an M1-or-later iPad, or another supported device.

## 1. Create the Shortcut

1. Open **Shortcuts**.
2. Tap **+** to create a new Shortcut.
3. Tap the Shortcut name at the top and name it exactly **Tom’s Diary Reply**.
4. Leave the editor open.

If you choose a different name, enter that exact same name in Tom’s Diary Settings later.

## 2. Add Tom’s Diary’s prompt action

1. Tap **Add Action**.
2. Search for **Tom’s Diary**.
3. Choose **Get Pending Diary Prompt**.
4. Tap the action’s **Request Handle** field.
5. Choose the **Shortcut Input** special variable as its **Request Handle** value. To find it, tap and hold the field, then choose **Select Variable → Shortcut Input**.

Tom’s Diary supplies Shortcut Input automatically. It is an opaque, expiring request handle containing a request ID and cryptographically random capability; it contains no diary text. This action uses that capability to obtain the frozen prompt, including recognized writing and relevant local history. The prompt is never placed in the URL that launches Shortcuts.

## 3. Add ChatGPT generation

1. Tap **Add Action**.
2. Search for **Use Model** and add it.
3. Tap the selected model and choose **Extension Model**, then choose **ChatGPT**.
4. Tap the prompt field and choose the output of **Get Pending Diary Prompt**.
5. Tap the disclosure arrow on the Use Model action.
6. Turn **Follow Up** off.

Do not add a **Show Result**, **Quick Look**, **Copy to Clipboard**, or sharing action. The response will be passed directly to Tom’s Diary instead of being displayed in Shortcuts.

## 4. Return the reply to Tom’s Diary

1. Tap **Add Action**.
2. Search for **Tom’s Diary**.
3. Choose **Complete Diary Reply**.
4. Set **Request Handle** to **Shortcut Input**.
5. Set **Reply** to the response from **Use Model**.
6. Tap **Done** to save the Shortcut.

The Shortcut should now have exactly these actions, in this order:

```text
Get Pending Diary Prompt       (Request Handle = Shortcut Input special variable)
Use Model                      (Extension Model = ChatGPT; Prompt = previous output)
Complete Diary Reply           (Request Handle = Shortcut Input special variable; Reply = Use Model response)
```

The final action saves the response and reopens Tom’s Diary. That is the only place the reply should be displayed.

## 5. Match the Shortcut name in Tom’s Diary

1. Open **Tom’s Diary**.
2. Open **Settings**.
3. Enter **Tom’s Diary Reply** in the Reply Shortcut Name field.
4. If you used another name in Step 1, enter that exact name instead.
5. Tap the small info button for a summary or **Setup Guide** to reopen these instructions.
6. Tap **Test Shortcut**. Tom’s Diary verifies the configured name and the complete round trip using a setup probe that is never added to diary history.
7. Wait for Settings to show the verified name and time. Merely opening Shortcuts does not count as successful verification.

## 6. Test it

1. Write a short line in the diary.
2. Stop writing for about three seconds.
3. Tom’s Diary recognises the writing and starts your Shortcut automatically.
4. Wait for Tom’s Diary to return to the foreground.
5. The generated reply appears on the same diary page and the canvas remains intact.

Shortcuts may temporarily appear and may retain execution history. The Shortcut does not contain a result-display action, and Tom’s Diary returns to the same uncleared canvas when completion succeeds.

## Troubleshooting

### I cannot find “Use Model” or “ChatGPT”

Apple Intelligence or the ChatGPT extension is unavailable on this device. Confirm the device is compatible, Apple Intelligence is enabled, the device and Siri language are supported, and ChatGPT is enabled under **Settings → Apple Intelligence & Siri → ChatGPT**.

### I cannot find Tom’s Diary actions

Open Tom’s Diary once after installing/updating it, then close and reopen Shortcuts. Look under the Tom’s Diary app actions. If they remain absent, reinstall the current app build and try again.

### Tom’s Diary says the Shortcut could not start

Check that the Shortcut name in Settings matches its name in Shortcuts exactly, including punctuation and spaces. Do not rename the Shortcut without updating Settings.

After changing the name, tap **Test Shortcut** again. Tom’s Diary cannot inspect a named Shortcut in advance; only a successful end-to-end test marks it verified.

### The Shortcut asks me to choose a Request Handle or Reply

Open the relevant action and reassign its variables:

- Both **Request Handle** fields must use **Shortcut Input**.
- **Use Model** must use the output from **Get Pending Diary Prompt**.
- **Complete Diary Reply → Reply** must use the response from **Use Model**.

### The reply is shown in Shortcuts

Remove any **Show Result**, **Quick Look**, **Copy to Clipboard**, share, or notification action that receives the Use Model response. Ensure **Follow Up** is turned off in Use Model.

### The iPad mini 6 does not show the ChatGPT extension

That is expected. The iPad mini 6 does not support Apple Intelligence, which is required for the Extension Model path. The Shortcut can be created and run on a supported device instead.

### A run was cancelled or failed

Return to Tom’s Diary and choose Retry. Retry reuses the same frozen prompt and request identity with newly rotated security capabilities. It does not add a history entry by itself, and eventual successful completion can add at most one diary turn even if completion or activation is delivered more than once.

## Privacy

Tom’s Diary launches Shortcuts with an opaque, expiring capability handle only. The first Tom’s Diary action retrieves the prepared prompt; the last action stores the answer locally and returns to the diary. The canvas image is never sent to Shortcuts or ChatGPT. Capability secrets are not stored in plaintext and are not written to logs. Shortcuts may retain its own execution history. The ChatGPT portion is governed by Apple Intelligence settings and, when you optionally sign in, your ChatGPT account settings.
