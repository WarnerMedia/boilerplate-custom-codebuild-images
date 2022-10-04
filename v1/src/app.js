'use strict';

/**
 * Set some constants.
 */

// Load some packages.
const AWS = require('aws-sdk');
const GitHub = require('github-api');
const got = require('got');

// The current environment for this function.
const environment = process.env.ENVIRONMENT;
const githubApiBase = "https://api.github.com/repos/";
// The current region for this function.
const region = process.env.REGION;
// The ARN of the Webhook URL secret.
const secretTokenArn = process.env.SECRET_TOKEN_ARN;

/**
 * Set some global variables.
 */

let decodedBinarySecret,
  gh,
  jobId,
  params,
  repo,
  secret,
  token;

/**
 * Create some instances.
 */

let client = new AWS.SecretsManager({
  region: region
});

let codepipeline = new AWS.CodePipeline();

/**
 * Create some functions.
 */

function buildReleaseBody(owner,repository,current,previous) {
  let body = "(Initial Release)";

  if (previous != "none") {
    body = `[ [Release Changelog](https://github.com/${owner}/${repository}/compare/${previous}...${current}) ]`;
  }

  return body;

}

function createBranch(context,branch,sha) {

  let options = {
    "ref": `refs/heads/${branch}`,
    "sha": sha
  };

  repo.createRef(options).then(function({data}) {
    putJobSuccess(context, "GitHub Branch Created");
  }).catch(function({data}) {
    putJobFailure(context, "GitHub Branch Creation Failed");
  });
}

function createRelease(context) {

  let options = {
    tag_name: params.currentRelease,
    target_commitish: params.commit,
    name: params.currentRelease,
    body: buildReleaseBody(params.owner,params.repository,params.currentRelease,params.prevRelease),
    draft: false,
    prerelease: (params.prerelease === "true" ? true : false)
  };

  repo.createRelease(options).then(function({data}) {
    putJobSuccess(context, "GitHub Release Created");
  }).catch(function({data}) {
    putJobFailure(context, "GitHub Release Creation Failed");
  });

}

function createUnstableBranch(context) {

  repo.getBranch(params.unstableBranch).then(function({data}) {

    console.info("Branch already exists, will update based on SHA...");
    updateBranch(context,params.unstableBranch,params.commit);

  }).catch(function({data}) {

    console.info("Branch doesn't exist, will create based on SHA...");
    createBranch(context,params.unstableBranch,params.commit);

  });

}

function updateBranch(context,branch,sha) {

  repo.updateHead(`heads/${branch}`,sha,true).then(function({data}) {
    putJobSuccess(context, "GitHub Branch Updated");
  }).catch(function({data}) {
    putJobFailure(context, "GitHub Branch Update Failed");
  });

}

function updateRelease(context) {

  // 2021.01.16: Having to fall back to a raw got request because the GitHub API module currently doesn't support getting a release by tag.
  let requestUrl = `${githubApiBase}${params.owner}/${params.repository}/releases/tags/${params.currentRelease}`;

  got(requestUrl, {
    headers: {
      'authorization': `token ${token}`
      }
  }).then(response => {
    repo.updateRelease(JSON.parse(response.body).id,{
      prerelease: (params.prerelease === "true" ? true : false)
    }).then(function({data}) {
      putJobSuccess(context, "GitHub Release Updated");
    }).catch(function({data}) {
      putJobFailure(context, "GitHub Release Update Failed");
     });
  }).catch(error => {
    putJobFailure(context, "Failed to retrieve GitHub Release information.");
  });

}

function getSecret(event, context, callback, secretTokenArn) {
  client.getSecretValue({SecretId: secretTokenArn}, function(err, data) {
    if (err) {

      console.warn(`Secrets Manager Error: ${err.code}`);

      putJobFailure(context, `Secrets Manager Error: ${err.code}`);

      if (err.code === 'DecryptionFailureException')
        // Secrets Manager can't decrypt the protected secret text using the provided KMS key.
        // Deal with the exception here, and/or rethrow at your discretion.
        throw err;
      else if (err.code === 'InternalServiceErrorException')
        // An error occurred on the server side.
        // Deal with the exception here, and/or rethrow at your discretion.
        throw err;
      else if (err.code === 'InvalidParameterException')
        // You provided an invalid value for a parameter.
        // Deal with the exception here, and/or rethrow at your discretion.
        throw err;
      else if (err.code === 'InvalidRequestException')
        // You provided a parameter value that is not valid for the current state of the resource.
        // Deal with the exception here, and/or rethrow at your discretion.
        throw err;
      else if (err.code === 'ResourceNotFoundException')
        // We can't find the resource that you asked for.
        // Deal with the exception here, and/or rethrow at your discretion.
        throw err;
    } else {
      // Decrypts secret using the associated KMS CMK.
      // Depending on whether the secret is a string or binary, one of these fields will be populated.
      if ('SecretString' in data) {
        secret = data.SecretString;
      } else {
        let buff = new Buffer(data.SecretBinary, 'base64');
        decodedBinarySecret = buff.toString('ascii');
      }
    }
    
    token = JSON.parse(secret).oAuthToken;
    processEvent(context); 
  });
}

function processEvent(context) {

  console.info("About to list out the user parameters...");
  console.dir(params);

  gh = new GitHub({
    token: token
  });

  repo = gh.getRepo(params.owner,params.repository);

  switch(params.mode) {
    case "createRelease":
      createRelease(context);
      break;
    case "createUnstableBranch":
      createUnstableBranch(context);
      break;
    case "updateRelease":
      updateRelease(context);
      break;
    default:
      putJobFailure(context, "No release mode was set.");
  }
}

function putJobSuccess(context,message) {

  var params = {
    jobId: jobId
  };

  codepipeline.putJobSuccessResult(params, function(err, data) {
    if(err) {
      context.fail(err);
    } else {
      context.succeed(message);
    }
  });
};

function putJobFailure(context,message) {

  var params = {
    jobId: jobId,
    failureDetails: {
      message: JSON.stringify(message),
      type: 'JobFailed',
      externalExecutionId: context.awsRequestId
    }
  };
  codepipeline.putJobFailureResult(params, function(err, data) {
    context.fail(message);    
  });
};

/**
 * Main logic.
 */

exports.handler = (event, context, callback) => {

  // Retrieve the Job ID from the Lambda action.
  jobId = event["CodePipeline.job"].id;

  //Parse the UserParameters string as JSON.
  params = JSON.parse(event["CodePipeline.job"].data.actionConfiguration.configuration.UserParameters);

  console.log(`The Job ID is: ${jobId}`);

  if (token) {

    // Container reuse, simply process the event with the key in memory.
    processEvent(context);

  } else if (secretTokenArn) {

    getSecret(event, context, callback, secretTokenArn);

  } else {

    putJobFailure(context, 'Token value has not been set.');

    callback('Token value has not been set.');

  }
};