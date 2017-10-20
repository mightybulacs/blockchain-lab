'use strict';

const hfc   = require('fabric-client');
const path  = require('path');

const options = {
    wallet_path: path.join(__dirname, './creds'),
    user_id: 'StoreAdmin',
    channel_id: 'mychannel',
    chaincode_id: 'docutrack',
    network_url: 'grpc://localhost:7051'
};

const channel = {};
let client = null;

Promise.resolve().then(() => {
    console.log('creating a client and setting the wallet location...');
    client = new hfc();
    return hfc.newDefaultKeyValueStore({path: options.wallet_path});
}).then((wallet) => {
    console.log('setting wallet path and associating user ', options.user_id, ' with application');
    client.setStateStore(wallet);
    return client.getUserContext(options.user_id, true);
}).then((user) => {
    console.log('checking user enrolment and setting a query url in the network');
    if (user === undefined || user.isEnrolled() === false) {
        console.error('[error] user is neither defined nor enrolled');
    }
    channel = client.newChannel(options.channel_id);
    channel.addPeer(client.newPeer(options.network_url));
    return;
}).then(() => {
    console.log('querying...');
    const transaction_id = client.newTransactionID();
    console.log('assigning transaction_id', transaction_id._transaction_id);
    const request = {
        chaincodeId: options.chaincode_id,
        txId: transaction_id,
        fcn: 'queryCar',
        args: ['CAR1']
    };
    return channel.queryByChaincode(request);
}).then((query_responses) => {
    console.log('returned from querying');
    if (!query_responses.length) {
        console.log('no payloads were returned from query');
    } else {
        console.log('query result count = ', query_responses.length);
    }
    if(query_responses[0] instanceof Error) {
        console.error('[error] query = ', query_responses[0]);
    }
    console.log('response is ', query_responses[0].toString());
}).catch((err) => {
    console.error('[error]', err);
});
