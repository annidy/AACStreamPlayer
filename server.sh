#!/bin/sh

while true; 
do 
	cat sample.aac|nc -l 9999
done
