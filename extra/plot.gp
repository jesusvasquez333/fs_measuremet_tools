set term png
set output output_file
set xlabel "Iteration"
set xtics 1
set ylabel "Rate"
set y2label "Free RAM"
set y2tics
set grid
plot input_file using 1 with lines axis x1y2 title 'Free RAM before', '' using 3 with lines axis x1y2 title 'Free RAM after', '' using 5 with lines axis x1y1 title 'Rate'