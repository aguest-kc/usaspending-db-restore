#!/bin/bash

# Set all of the variables needed
CONN="postgresql://${DBUSER}:${DBPASSWORD}@${DBHOST}:${DBPORT}"
DUMP_DIR=/usaspending/usaspending-db-subset_20220510
DUMP=$DUMP_DIR/pruned_data_store_api_dump


install_required_software() {
    echo -e "Installing pg_restore\n"
    sleep 1
    yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    yum check-update -y
    yum install -y postgresql14-server
}

drop_and_create_database() {
    echo -e "This will drop your current data_store_api database and then recreate it.\n"
    read -r -p "Are you sure you want to continue? [Y/n] " input

    case $input in
        [yY][eE][sS]|[yY])
            echo -e "Droping data_store_api database\n"
            psql $CONN/postgres -c "DROP DATABASE IF EXISTS $DBNAME"
            echo -e "Creating data_store_api database\n"
            psql $CONN/postgres -c  "CREATE DATABASE $DBNAME"
            ;;
        [nN][oO]|[nN])
            echo "Exiting\n"
            exit 0
            ;;
        *)
            echo "Invalid input..."
            exit 1
            ;;
    esac 
}

restore_non_materialized_data() {
    # Create list of ALL EXCEPT materialized views data (defer them), to restore
    pg_restore --list $DUMP | sed '/MATERIALIZED VIEW DATA/d' > $DUMP_DIR/restore.list

    # Restore all but materialized view data
    echo -e "Restoring all but the materialized view data\n"
    sleep 2
    pg_restore \
        --jobs 16 \
        --dbname $CONN/$DBNAME \
        --verbose \
        --use-list $DUMP_DIR/restore.list \
        $DUMP

    # Perform an ANALYZE to optimize query performance in view materialization
    echo -e "\nPerforming ANALYZE to optimize query performance\n"
    sleep 2
    psql \
        --dbname $CONN/$DBNAME \
        --command 'ANALYZE VERBOSE;' \
        --echo-all \
        --set ON_ERROR_STOP=on \
        --set VERBOSITY=verbose \
        --set SHOW_CONTEXT=always
}

restore_materialized_data() {
    echo -e "This will restore the materialized views.\n"
    echo -e "Restoring the materialized views is optional, but not restoring them will affect your ability to run the USAspending API, as it relies on these materialized views. The materialized views require a fair amount of extra space, which is why this step is optional (but encouraged).\n"
    read -r -p "Do you want to restore the materialized views? [Y/n] " input

    case $input in
        [yY][eE][sS]|[yY])
            echo -e "Restoring materialized view\n"
            sleep 2
            pg_restore --list $DUMP | grep "MATERIALIZED VIEW DATA" > $DUMP_DIR/refresh.list
            pg_restore \
                --jobs 16 \
                --dbname $CONN/$DBNAME \
                --verbose \
                --use-list $DUMP_DIR/refresh.list \
                $DUMP

            echo -e "Performing ANALYZE on the materialized views\n"
            sleep 2
            pg_restore --list $DUMP \
                | grep "MATERIALIZED VIEW DATA" \
                | awk '{ print "ANALYZE VERBOSE", $8";" };' \
                > $DUMP_DIR/analyze_matviews.sql

            psql \
                --dbname $CONN/$DBNAME \
                --echo-all \
                --set ON_ERROR_STOP=on \
                --set VERBOSITY=verbose \
                --set SHOW_CONTEXT=always \
                --file $DUMP_DIR/analyze_matviews.sql

            ;;
        [nN][oO]|[nN])
            echo "Skipping the materialized views\n"
            exit 0
            ;;
        *)
            echo "Invalid input..."
            exit 1
            ;;
    esac
}

main() {
    clear
    echo -e "\nThis script is used to populate your local development database with a subset of USA Spending's production data.\n"
    echo -e "----------------------------------------------------------------------------\n"
    install_required_software
    echo -e "----------------------------------------------------------------------------\n"
    sleep 3
    drop_and_create_database
    echo -e "----------------------------------------------------------------------------\n"
    sleep 3
    clear
    restore_non_materialized_data
    echo -e "----------------------------------------------------------------------------\n"
    sleep 3
    restore_materialized_data
}


main
