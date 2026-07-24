import { CognitoUserPool, CognitoUser, AuthenticationDetails } from "amazon-cognito-identity-js";
import { cfg } from "./config";

const pool = new CognitoUserPool({ UserPoolId: cfg.poolId, ClientId: cfg.clientId });

export function login(email, password) {
  return new Promise((resolve, reject) => {
    const user = new CognitoUser({ Username: email, Pool: pool });
    user.authenticateUser(
      new AuthenticationDetails({ Username: email, Password: password }),
      {
        onSuccess: (s) => resolve(s.getIdToken().getJwtToken()),
        onFailure: reject,
      }
    );
  });
}
