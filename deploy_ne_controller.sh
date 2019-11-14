source scripts/ansible-precheck.sh

ansible-playbook -vv \
    ./ne_controller.yml \
    --inventory inventory.ini
