## 1.0.0

- First release.
- Android through Firebase Cloud Messaging, iOS through APNs directly, with images and action buttons.
- Same calls as `onesignal_flutter` v5 under `Takeed`: `initialize`, `login`, `logout`, tags, permission, click and foreground listeners, push subscription observers.
- Branches: tie a device to a branch with `Takeed.initialize(..., branch: 'north')`.
- Identity verification with `Takeed.login(id, identityHash: ...)`.
