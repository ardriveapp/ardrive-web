# Deploy to Arweave

The deployer app here uses [permaweb-deploy](https://github.com/permaweb/permaweb-deploy) to deploy the ArDrive app to Arweave and update the ArNS name to point to the new deployment. Developers can deploy their own versions of the application to arweave using `yarn deploy`.

Note: The application must be built in the root folder for web prior to using `yarn deploy

Running `yarn deploy` uses the following environment variables:

```
export DEPLOY_ANT_PROCESS_ID=[process id of the ant process to deploy to]
export DEPLOY_ANT_UNDERNAME=[undername to deploy to]
export DEPLOY_KEY=[base64 encoded version of wallet keyfile]
```

For local testing, you can create a deploy.sh script with the above values defined, run `source deploy.sh`, then use `yarn deploy`.
