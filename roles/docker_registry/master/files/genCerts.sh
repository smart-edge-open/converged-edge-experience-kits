#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

helpPrint()
{
   echo ""
   echo "Usage: $0 [-t sanType -h {sanValue | *}] | *"
   echo -e "\t-t SAN type: could be IP or DNS"
   echo -e "\t-h subject alternative names list: could be one or more IP addressess or domain names separated by space"
   echo -e "\t"
   echo -e "Ex: $0 -t DNS -h afservice nefservice localhost"
   echo -e "    $0 -t IP -h 172.168.10.12 172.168.10.56"
   echo -e "    $0 -t DNS -h controller -t IP -h 172.168.10.12 172.168.10.56"
   echo -e "    $0 -t IP -h 172.168.10.12 -t DNS -h afservice nefservice localhost"
   echo -e ""
   exit 1 # Exit with help
}

Hostname_count=0
Hostname_flag=0
IP_count=0
IP_flag=0
subjstr=""
subj1=""
tupleStarted=0

while [ "$1" != "" ]; 
do
   case $1 in
      -t )
         if [ $tupleStarted == 1 ]
         then
            echo "Missing -h option"
            helpPrint
         else
            tupleStarted=1
         fi
         if [ $Hostname_flag == 1 ]
         then
            Hostname_flag=0
         fi
         if [ $IP_flag == 1 ]
         then
            IP_flag=0
         fi
         shift 
         if [ "$1" == IP ] || [ "$1" == DNS ] 
         then
            sanType="$1"
         else
            echo "Missing/Wrong sanType"
            helpPrint
         fi
         ;;
      -h )
         if [ "$sanType" == "" ] || [ $Hostname_flag != 0 ] || [ $IP_flag != 0 ]
         then
            echo "Missing -t option"
            helpPrint
         fi
         shift
         if [ "$1" != "" ] && [ "$1" != "-t" ] && [ "$1" != "-h" ]
         then
            tupleStarted=0
            if [ "$subj1" == "" ]
            then
               subj1="$1"
            fi
            if [ "$sanType" == DNS ]
            then
               Hostname_flag=$((Hostname_flag+1))
               Hostname_count=$((Hostname_count+1))
               if [ "$subjstr" == "" ]
               then
                  subjstr=$sanType"."$Hostname_count":""$1"
               else
                  subjstr+=","$sanType"."$Hostname_count":""$1"
               fi
            fi
            if [ "$sanType" == IP ]
            then
               IP_flag=$((IP_flag+1))
               IP_count=$((IP_count+1))
               if [ "$subjstr" == "" ]
               then 
                  subjstr=$sanType"."$IP_count":""$1"
               else
                  subjstr+=","$sanType"."$IP_count":""$1"
               fi
            fi
         else
            echo "Missing argument for -h option"
            helpPrint
         fi
         ;;
      ? ) helpPrint # Print help
         ;;
      * )
         if [ $Hostname_flag == 1 ]
         then
            Hostname_count=$((Hostname_count+1))
            subjstr+=","$sanType"."$Hostname_count":""$1"
         elif [ $IP_flag == 1 ]
         then
            IP_count=$((IP_count+1))
            subjstr+=","$sanType"."$IP_count":""$1"
         else
            echo "Incorrect Input"
            helpPrint
         fi
         ;;
  esac
  shift
done

if [ $tupleStarted != 0 ]
then
   echo "Missing -h option "
   helpPrint
fi

if [ -z "$subj1" ] || [ -z "$subjstr" ] || [ -z "$sanType" ]
then
   echo "One of the input parameters missing"
   helpPrint
fi

echo "Running with input parameters:"
echo "$subjstr"

ROOT_CA_NAME=DOCKER-REGISTRY

echo "Generating RootCA Key and Cert:"
openssl ecparam -genkey -name secp384r1 -out "root-ca-key.pem"
if (($?))
then 
   echo "RootCA key generation failed"
   exit 1
fi

openssl req -key "root-ca-key.pem" -new -x509 -days 90 -subj "/CN=$ROOT_CA_NAME" -out "root-ca-cert.pem" 
if (($?))
then 
   echo "RootCA cert generation failed"
   exit 1
fi

echo "Generating Server Key and Cert:"
openssl ecparam -genkey -name secp384r1 -out "server-key.pem"
if (($?))
then 
   echo "Server key generation failed"
   exit 1
fi

openssl req -new -key "server-key.pem" -out "server-request.csr" -subj "/CN=$subj1"
if (($?))
then 
   echo "Server CSR generation failed"
   exit 1
fi
rm -f extfile.cnf
echo "subjectAltName = $subjstr" >> extfile.cnf
openssl x509 -req -extfile extfile.cnf -in "server-request.csr" -CA "root-ca-cert.pem" -CAkey "root-ca-key.pem" -days 90 -out "server-cert.pem" -CAcreateserial
if (($?))
then 
   echo "Server cert generation failed"
   exit 1
fi

echo "Print CA Cert Pem:"
openssl x509 -in root-ca-cert.pem -text -noout
echo "Print Server Cert Pem:"
openssl x509 -in server-cert.pem -text -noout
echo "Successfully completed"
