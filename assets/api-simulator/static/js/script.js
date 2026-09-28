$(document).ready(function () {
    $('.tabContent').hide();

    $('#tabs li a').click(function () {
        var t = $(this).attr('href');
        $('#tabs li').removeClass('active');
        $(this).parent('li').addClass('active');
        $('.tabContent').hide();

        $(t).fadeIn('slow');
        if(t == "#books"){
            populateBooksTable('/api/v1/books');
        }
    })



    // Load the books file (if it exists)
    function populateBooksTable(url, thread){
        if(!thread && $('#books-content').attr("locked")){
            console.log("Table is already locked by other thread ...");
            return
        }
            
        if(!thread){
            console.log("Starting a new thread...")
            thread = Date.now();
            $('#books-content').attr("locked", thread);
            $('#books-content').empty();
        }

        if($('#books-content').attr("locked") && $('#books-content').attr("locked") != thread){
            console.log("Table is locked by other thread ...");
            return;
        }
        
        $.getJSON(url, 
            function (data, textStatus, jqXHR) {
                data.forEach(function (book, i) {
                    var tr = '<tr><td>' + book.id + '</td><td>' + book.title + '</td><td>';
                    tr += book.author + '</td></tr>';
                    $('#books-content').append(tr);
                })
                
                var link = jqXHR.getResponseHeader('Link');
                if(link){
                    var regex = /<([^>]+)>; rel="next"/;
                    var regexResults = regex.exec(link);
                    if(regexResults){
                        nextLink = regexResults[1];
                        console.log("next link = " + nextLink);
                        populateBooksTable(nextLink, thread);
                    }
                }else{
                    $('#books-content').removeAttr("locked")
                }
            } 
        ).fail(function (jqXHR) {
            if(jqXHR.status == 429){
                console.log("Too many requests - retrying...");
                var retryAfter = jqXHR.getResponseHeader("Retry-After");
                $('#books-content').append("<tr id='loadingInfoRow'><td>Loading in " + retryAfter + " seconds ...</td></tr>");
                setTimeout(function() {
                        $("#loadingInfoRow").remove();
                        populateBooksTable(url, thread);
                    }, 
                    retryAfter * 1000
                );
            }else{
                console.log("Error " + jqXHR.status + " / " + jqXHR.statusText);
                console.log(responseText);
            }
            //$('#tabs li a:first').trigger('click');
        })
    }
    //populateBooksTable('/api/v1/books');
    $('#tabs li a:first').trigger('click');
});
