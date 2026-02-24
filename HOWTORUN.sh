## Prerequisites

# 1 : Check that docker is working 
# Power shell (PS) commands are prefixed with >>

>> docker --version
>> docker compose version

# 2 : Copy .env.example to .env to ensure that the environment variables are set up correctly 
# and DB will be on localhost:5432

>> copy .env.example .env 

# 3. Staring Postgres with Docker compose
>> docker compose up -d
# (to check if the container is running, you can use >> docker compose ps)

# 4. Run the migrations using the goose-docker image
# note that the port is 5433 because we are forwarding the container's 5432 to our localhost's 5433
# This project uses the kukymbr/goose-docker image.

>> docker run --rm `
>>  -v "${PWD}\db\migrations:/migrations" `
>>  -e GOOSE_DRIVER="postgres" `
>>  -e GOOSE_DBSTRING="host=host.docker.internal port=5433 user=postgres password=postgres dbname=barcode_db sslmode=disable" `
>>  kukymbr/goose-docker:latest

____________________________________________________________________________________________________________

## 5. Inspect database schema
>> docker compose exec db psql -U postgres -d barcode_db -c "\d+ dirac.product"

## 6a. How to run seed_products.sql to insert sample data into the database
>> Get-Content .\seed_products.sql -Raw | docker compose exec -T db psql -U postgres -d barcode_db

## 6b. How I piped this output to a file for the write-up
## Output for this demo is located in .\seed_run_output.txt
>> Get-Content .\db\seed_products.sql -Raw |  docker compose exec -T db psql -U postgres -d barcode_db `  | Tee-Object -FilePath .\seed_run_output.txt