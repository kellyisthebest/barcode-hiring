## Prerequisites

# Check that docker is working 
>> docker --version
>> docker compose version

# Copy .env.example to .env to ensure that the environment variables are set up correctly 
# and DB will be on localhost:5432
>> copy .env.example .env 

# Staring Postgres with Docker compose
>> docker compose up -d
# (to check if the container is running, you can use >> docker compose ps)

# Run the migrations using the goose-docker image
# note that the port is 5433 because we are forwarding the container's 5432 to our localhost's 5433
>> docker run --rm `
>>  -v "${PWD}\db\migrations:/migrations" `
>>  -e GOOSE_DRIVER="postgres" `
>>  -e GOOSE_DBSTRING="host=host.docker.internal port=5433 user=postgres password=postgres dbname=barcode_db sslmode=disable" `
>>  kukymbr/goose-docker:latest

## Inspect the current table 
>> docker compose exec db psql -U postgres -d barcode_db -c "\d+ dirac.product"


