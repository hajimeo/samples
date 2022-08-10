# SQL client for PostgreSQL used by Nexus and (TODO) IQ
NOTE:  
No UPDATE/INSERT/DELETE support, read (SELECT) only.

## FEATURES:
- Database check
  - Get modified Postgres config
  - Running queries
  - Locks
  - Estimated Table sizes
- NXRM3: Get estimated size per repo / blobstore
- NXRM3: Export Component database
- NXIQ: ...

## COMMAND LINE OPTIONS
```
  -t    Type    Application Type [nxrm3|nxiq] and default is nxrm
  -c    Config  Path to nexus-store.properties or config.yml
  -a    Action  db-check|data-size|data-export
```

## USAGE EXAMPLE:
```
NexusSql -t nxrm3 -c ./etc/fabric/nexus-store.properties -a
```

## Misc. / TODO:
Export component database for NXRM3, which should be consumable with support.zip  
CSV format should work with COPY command with delimiter (https://linuxhint.com/postgresql-copy-stdin/ )