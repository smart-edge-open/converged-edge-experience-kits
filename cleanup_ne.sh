source scripts/ansible-precheck.sh

ansible-playbook -vv \
    ./ne_cleanup.yml \
    --inventory inventory.ini
