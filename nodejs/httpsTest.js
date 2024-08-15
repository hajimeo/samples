/*
 1. Create this file
 2. npm init -y
 3. npm install axios
 4. node httpsTest.js
 */
const axios = require('axios');

async function fetchData() {
    try {
        const response = await axios.get('https://nxiqha-k8s.standalone.localdomain/ping');
        console.log(response.data);
    } catch (error) {
        console.error(error);
    }
}

fetchData();
