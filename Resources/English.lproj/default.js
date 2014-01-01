// Insert your JavaScript code here

var margin = {top: 20, right: 20, bottom: 20, left: 20};
var width = window.innerWidth - margin.left - margin.right;
var height = window.innerHeight - margin.top - margin.bottom;

var svg = d3.select("body").append("svg")
    .attr("width", width + margin.left + margin.right)
    .attr("height", height + margin.top + margin.bottom)
    .append("g")
    .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

svg.selectAll("circle")
    .data(data)
    .enter()
    .append("circle")
    .attr("class", "circle")
    .attr("cx", width / 2)
    .attr("cy", height / 2)
    .attr("r", function(d) {return d.radius; } );
