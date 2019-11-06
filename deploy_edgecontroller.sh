source scripts/ansible-precheck.sh

ansible-playbook -vv -i inventory.ini controller.yml \
    --skip-tags=docker_prune #,uninstall,cleanup
