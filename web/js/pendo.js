
function initializePendo(publicKeyMD5Hash) {
    /* example options
    const exampleOpts = {
        visitor: {
            id:              'VISITOR-UNIQUE-ID'   // Required if user is logged in
            // email:        // Recommended if using Pendo Feedback, or NPS Email
            // full_name:    // Recommended if using Pendo Feedback
            // role:         // Optional
    
            // You can add any additional visitor level key-values here,
            // as long as it's not one of the above reserved names.
        },
    
        account: {
            id:           'ACCOUNT-UNIQUE-ID' // Highly recommended
            // name:         // Optional
            // is_paying:    // Recommended if using Pendo Feedback
            // monthly_value:// Recommended if using Pendo Feedback
            // planLevel:    // Optional
            // planPrice:    // Optional
            // creationDate: // Optional
    
            // You can add any additional account level key-values here,
            // as long as it's not one of the above reserved names.
        }
    };*/
    try {
        pendo.initialize({
            'visitor': {
                'id':              publicKeyMD5Hash // Required if user is logged in
                // email:        // Recommended if using Pendo Feedback, or NPS Email
                // full_name:    // Recommended if using Pendo Feedback
                // role:         // Optional
        
                // You can add any additional visitor level key-values here,
                // as long as it's not one of the above reserved names.
            }
        });
    } catch(err) {
        console.log("PENDO ERROR: " + err);
    }
}
