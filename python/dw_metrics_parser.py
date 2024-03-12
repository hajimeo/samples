import requests
import pandas as pd

# Fetch the JSON data from the Dropwizard metrics endpoint
response = requests.get('http://localhost:8071/metrics')
data = response.json()

# Load the JSON data into a Pandas DataFrame
dfs = {}
for k in data.keys():
    if isinstance(data[k], dict) or isinstance(data[k], list):
        dfs[k] = pd.json_normalize(data[k])
#dfs.keys()

# Now you can analyze the data using Pandas
# For example, to view the first few rows of the DataFrame
for k in dfs.keys():
    print(f'# First {k}')
    print(dfs[k].iloc[0])

# Actually each key contains one row, above is not so useful.
