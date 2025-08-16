#!/bin/bash

# Перебираем все файлы, соответствующие шаблону photo_*@*.jpg
for file in *_*@*.*; do
    # Проверяем, существует ли файл (на случай, если нет подходящих)
    if [ -f "$file" ]; then
        # Извлекаем части из имени файла
        # Формат: photo_NNN@DD-MM-YYYY_HH-MM-SS.jpg
        prefix=$(echo "$file" | cut -d'@' -f1)  # photo_NNN
        datetime_part=$(echo "$file" | cut -d'@' -f2 | cut -d'.' -f1)  # DD-MM-YYYY_HH-MM-SS
        ext=$(echo "$file" | cut -d'.' -f2)
        date_part=$(echo "$datetime_part" | cut -d'_' -f1 )  # DD-MM-YYYY
        time_part=$(echo "$datetime_part" | cut -d'_' -f2 )  # HH-MM-SS
        
        # Извлекаем компоненты даты
        day=$(echo "$date_part" | cut -d'-' -f1)
        month=$(echo "$date_part" | cut -d'-' -f2)
        year=$(echo "$date_part" | cut -d'-' -f3)
        hour=$(echo "$time_part" | cut -d'-' -f1)
        minute=$(echo "$time_part" | cut -d'-' -f2)
        second=$(echo "$time_part" | cut -d'-' -f3)
        
        # Извлекаем NNN из photo_NNN
        if [[ "$file" =~ photo_([0-9]+) ]]; then
            number=${prefix#photo_}
        else
          if [[ "$file" =~ video_([0-9]+) ]]; then
            number=${prefix#video_}
          else
            echo "Пропускаем файл: $file"
            continue
          fi
        fi
        # Формируем новое имя файла
        new_name_short="${year}-${month}-${day}_${hour}-${minute}-${second}.${ext}"
        new_name="${year}-${month}-${day}_${hour}-${minute}-${second}-${number}.${ext}"
        
        [ -f "$new_name_short" ] && mv -v "$file" "$new_name" || mv -v "$file" "$new_name_short"

        # Переименовываем файл
        # mv -v "$file" "$new_name"
        # echo "$new_name"
    fi
done

echo "Готово!"