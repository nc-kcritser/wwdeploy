#!/bin/bash

# Generate genders file from Warewulf node list

collapse_ranges() {
    local prev_name prev_num prev_profile start_num
    
    while IFS=' ' read node profile; do
        # Extract trailing digits: testnode001 -> testnode, 001
        num="${node##*[!0-9]}"
        name="${node%$num}"
        
        if [[ "$name" != "$prev_name" ]] || [[ "$profile" != "$prev_profile" ]]; then
            if [[ -n "$prev_name" ]]; then
                if [[ "$start_num" == "$prev_num" ]]; then
                    echo "${prev_name}${prev_num} ${prev_profile}"
                else
                    printf "%s[%0*d-%0*d] %s\n" "$prev_name" ${#prev_num} $start_num ${#prev_num} $prev_num "$prev_profile"
                fi
            fi
            start_num="$num"
        elif [[ $((10#$num - 10#$prev_num)) -ne 1 ]]; then
            if [[ "$start_num" == "$prev_num" ]]; then
                echo "${prev_name}${prev_num} ${prev_profile}"
            else
                printf "%s[%0*d-%0*d] %s\n" "$prev_name" ${#prev_num} $start_num ${#prev_num} $prev_num "$prev_profile"
            fi
            start_num="$num"
        fi
        
        prev_name="$name"
        prev_num="$num"
        prev_profile="$profile"
    done
    
    if [[ -n "$prev_name" ]]; then
        if [[ "$start_num" == "$prev_num" ]]; then
            echo "${prev_name}${prev_num} ${prev_profile}"
        else
            printf "%s[%0*d-%0*d] %s\n" "$prev_name" ${#prev_num} $start_num ${#prev_num} $prev_num "$prev_profile"
        fi
    fi
}

# Generate genders file
wwctl node list --json | \
    jq -r 'to_entries[] | "\(.key) \(.value.profiles | map(select(. != "default")) | join(","))"' | \
    sort | \
    collapse_ranges > /etc/genders

echo "Generated /etc/genders"
