## 2.0.0

- The SDK talks only to Takeed at `https://takeed-iq.com`. `initialize` no longer takes `apiUrl`:
  call `Takeed.initialize(appId)` (and `branch:` if you use branches).
- Delivery receipts and clicks always go to `takeed-iq.com`, never to an address in the message.

## 1.0.0

- First release.
- Android through Firebase Cloud Messaging, iOS through APNs directly, with images and action buttons.
- Same calls as `onesignal_flutter` v5 under `Takeed`: `initialize`, `login`, `logout`, tags, permission, click and foreground listeners, push subscription observers.
- Branches: tie a device to a branch with `Takeed.initialize(..., branch: 'north')`.
- Identity verification with `Takeed.login(id, identityHash: ...)`.
