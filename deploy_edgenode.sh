source scripts/ansible-precheck.sh

ansible-playbook -i inventory.ini edgenode.yml \
--limit node01
